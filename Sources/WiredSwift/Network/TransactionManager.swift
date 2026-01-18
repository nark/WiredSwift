//
//  TransactionStore.swift
//  WiredSwift
//
//  Created by Rafaël Warnault on 05/01/2026.
//

actor TransactionManager {

    private var streams: [UInt32: AsyncThrowingStream<P7Message, Error>.Continuation] = [:]

    func register(
        transaction: UInt32,
        continuation: AsyncThrowingStream<P7Message, Error>.Continuation
    ) {
        streams[transaction] = continuation
    }

    func yield(transaction: UInt32, message: P7Message) {
        streams[transaction]?.yield(message)
    }

    func finish(transaction: UInt32) {
        streams[transaction]?.finish()
        streams.removeValue(forKey: transaction)
    }

    func fail(transaction: UInt32, error: Error) {
        streams[transaction]?.finish(throwing: error)
        streams.removeValue(forKey: transaction)
    }
}
