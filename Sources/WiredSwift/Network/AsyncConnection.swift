//
//  AsyncConnection.swift
//  WiredSwift
//
//  Created by Rafaël Warnault on 05/01/2026.
//

/// Errors that `AsyncConnection` can throw when sending or receiving messages.
public enum AsyncConnectionError: Error {
    /// Attempted to send a message while the socket is not connected.
    case notConnected
    /// The socket write returned `false` (e.g. the connection was lost mid-write).
    case writeFailed
    /// The server replied with a `wired.error` message; the associated value carries the full error message.
    case serverError(P7Message)
}

/// A `Connection` subclass that exposes a Swift async/await API.
///
/// Each outgoing message gets its own `AsyncThrowingStream`; callers await individual replies
/// via `sendAsync(_:)` or consume a multi-reply stream via `sendAndWaitMany(_:)`.
/// Internally a `TransactionManager` actor routes each incoming message to the correct stream.
open class AsyncConnection: Connection {

    private let transactions = TransactionManager()

    // MARK: - Public API

    /// Sends a message and awaits the first response for its transaction.
    ///
    /// Use this when the server replies with a single message (e.g. `wired.okay` or one data message).
    /// For requests that produce multiple replies before a `.done` sentinel, use `sendAndWaitMany(_:)`.
    ///
    /// - Parameter message: The `P7Message` to send. The transaction ID is set automatically.
    /// - Returns: The first reply received for this transaction, or `nil` if the stream closes without a value.
    /// - Throws: `AsyncConnectionError` or any underlying socket error.
    public func sendAsync(
        _ message: P7Message
    ) async throws -> P7Message? {

        let stream = try await sendAndWaitMany(message)

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()

        return first
    }

    /// Sends a message and returns a stream that yields every server reply until the transaction ends.
    ///
    /// The stream finishes automatically when the server sends `wired.okay` or a message whose name
    /// ends with `.done`. A `wired.error` reply terminates the stream with `AsyncConnectionError.serverError`.
    ///
    /// - Parameter message: The `P7Message` to send. The transaction ID is set automatically.
    /// - Returns: An `AsyncThrowingStream` that produces successive response messages for this transaction.
    /// - Throws: `AsyncConnectionError.notConnected` if the socket is not connected at call time.
    public func sendAndWaitMany(
        _ message: P7Message
    ) throws -> AsyncThrowingStream<P7Message, Error> {

        guard socket.connected else {
            throw AsyncConnectionError.notConnected
        }

        transactionCounter += 1
        let transaction = transactionCounter
        message.addParameter(field: "wired.transaction", value: transaction)

        let stream = AsyncThrowingStream<P7Message, Error> { continuation in
            Task {
                await transactions.register(
                    transaction: transaction,
                    continuation: continuation
                )

                if !socket.write(message) {
                    await transactions.fail(
                        transaction: transaction,
                        error: AsyncConnectionError.writeFailed
                    )
                }
            }
        }

        return stream
    }

    // MARK: - Incoming messages

    override func handleMessage(_ message: P7Message) {
        super.handleMessage(message)

        guard let transaction = message.uint32(forField: "wired.transaction") else {
            return
        }

        Task {
            switch message.name {

            case "wired.send_ping":
                super.pingReply()

            case "wired.error":
                await transactions.fail(
                    transaction: transaction,
                    error: AsyncConnectionError.serverError(message)
                )

            default:
                await transactions.yield(
                    transaction: transaction,
                    message: message
                )

                if message.name == "wired.okay"
                    || message.name.hasSuffix(".done") {

                    await transactions.finish(transaction: transaction)
                }
            }
        }
    }
}
