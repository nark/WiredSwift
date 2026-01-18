//
//  AsyncConnection.swift
//  WiredSwift
//
//  Created by Rafaël Warnault on 05/01/2026.
//

public enum AsyncConnectionError: Error {
    case notConnected
    case writeFailed
    case serverError(P7Message)
}

open class AsyncConnection: Connection {

    private let transactions = TransactionManager()

    // MARK: - Public API
    /// Envoie un message et attend UNE seule réponse
    /// (le premier message reçu pour cette transaction)
    public func sendAsync(
        _ message: P7Message
    ) async throws -> P7Message? {

        let stream = try await sendAndWaitMany(message)

        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()

        return first
    }

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
