//
//  BlockConnection.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 29/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// A `Connection` subclass that routes server replies to completion and progress blocks.
///
/// This provides a UIKit/AppKit-style callback API on top of `Connection`. Each `send` call
/// associates a transaction ID with one or two blocks; the matching block is invoked on the
/// main queue when the server's reply arrives.
open class BlockConnection: Connection {
    private let queue = DispatchQueue(label: "fr.read-write.WiredSwift.BlockConnection", attributes: .concurrent)

    var progressBlocks: [UInt32: (P7Message) -> Void] = [:]
    var completionBlocks: [UInt32: (P7Message?) -> Void] = [:]

    /// Sends a message and invokes `completionBlock` on the main queue with the server's terminal reply.
    ///
    /// The completion block receives `nil` when the socket is not connected or the write fails.
    ///
    /// - Parameters:
    ///   - message: The `P7Message` to send. The transaction ID is set automatically.
    ///   - completionBlock: Called on the main queue with the final reply (`wired.okay` / `.done` / `wired.error`),
    ///     or `nil` on send failure.
    public func send(message: P7Message, completionBlock: @escaping (P7Message?) -> Void) {
        self.transactionCounter += 1

        if self.socket.connected {
            message.addParameter(field: "wired.transaction", value: self.transactionCounter)

            if !self.socket.write(message) {
                completionBlock(nil)
            }

            queue.async(flags: .barrier) {
                self.completionBlocks[self.transactionCounter]  = completionBlock
            }
        } else {
            completionBlock(nil)
        }
    }

    /// Sends a message and invokes `progressBlock` for each intermediate reply, then `completionBlock` for the terminal reply.
    ///
    /// - Parameters:
    ///   - message: The `P7Message` to send. The transaction ID is set automatically.
    ///   - progressBlock: Called on the main queue for each non-terminal server message in this transaction.
    ///   - completionBlock: Called on the main queue with the final reply (`wired.okay` / `.done` / `wired.error`),
    ///     or `nil` on send failure.
    public func send(message: P7Message, progressBlock: @escaping (P7Message) -> Void, completionBlock: @escaping (P7Message?) -> Void) {
        self.transactionCounter += 1

        if self.socket.connected {
            message.addParameter(field: "wired.transaction", value: self.transactionCounter)

            if !self.socket.write(message) {
                completionBlock(nil)
            }

            queue.async(flags: .barrier) {
                self.progressBlocks[self.transactionCounter]    = progressBlock
                self.completionBlocks[self.transactionCounter]  = completionBlock
            }
        } else {
            completionBlock(nil)
        }
    }

    override func handleMessage(_ message: P7Message) {
        // lets delegate handled messages transparently
        super.handleMessage(message)

        guard let transaction = message.uint32(forField: "wired.transaction") else {
            return
        }

        switch message.name {
        case "wired.send_ping":
            super.pingReply()

        case "wired.error":
            queue.sync {
                if let completionBlock = completionBlocks[transaction] {
                    DispatchQueue.main.async {
                        completionBlock(message)
                    }

                    completionBlocks.removeValue(forKey: transaction)
                    progressBlocks.removeValue(forKey: transaction)
                }
            }

        default:
            if message.name == "wired.okay" || message.name.hasSuffix(".done") {
                queue.sync {
                    if let completionBlock = completionBlocks[transaction] {
                        DispatchQueue.main.async {
                            completionBlock(message)
                        }

                        completionBlocks.removeValue(forKey: transaction)
                        progressBlocks.removeValue(forKey: transaction)
                    }
                }
            } else {
                queue.sync {
                    if !progressBlocks.isEmpty {
                        if let progressBlock = progressBlocks[transaction] {
                            DispatchQueue.main.async {
                                progressBlock(message)
                            }
                        }
                    } else {
                        if let completionBlock = completionBlocks[transaction] {
                            DispatchQueue.main.async {
                                completionBlock(message)
                            }
                        }
                    }
                }
            }
        }
    }
}
