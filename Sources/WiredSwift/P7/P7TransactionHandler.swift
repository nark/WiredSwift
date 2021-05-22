//
//  P7TransactionHandler.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 16/05/2021.
//

import Foundation
import NIO

/// The P7TransactionHandler handles messages transactions in a way
/// that simulates synchronous communication, using semaphore.
/// It reads the Wired specification in order to anticipate sent messages that will
/// need to wait for a future reply, multiple replies, or no reply at all,
/// and then free the read lock whenever it is necessary.
public class P7TransactionHandler {
    private var socket:P7Socket!
    
    private  var transactionID:UInt32 = 0
    internal var transactions:[UInt32:P7Transaction] = [:]
    
    
    
    public init(socket:P7Socket) {
        self.socket = socket
    }
    
    
    
    
    public func send(message: P7Message, channel: Channel, originator: Originator, waitForReply: Bool = false) -> P7Message? {
        if waitForReply {
            self.transactionID += 1
            
            message.addParameter(field: "wired.transaction", value: self.transactionID)
        } else {
            if let t = message.uint32(forField: "wired.transaction") {
                self.transactionID = t
            }
        }
        
        let transaction = P7Transaction(message: message, socket: self.socket)
            
        if transaction == nil {
            Logger.error("Missing transaction ID, invalid message, abort")
            return nil
        }
        
        self.transactions[self.transactionID] = transaction
        
        if transaction!.send(channel: channel) {
            if waitForReply {
                transaction?.wait()
                
                return transaction?.reply
            }
        }
        
        return nil
    }
    
    
    
    
    
    public func receive(message: P7Message, originator: Originator) {
        guard let tid = message.uint32(forField: "wired.transaction") else {
            return
        }
        
        var transaction = self.transactions[tid]
        
        if transaction == nil {
            transaction = P7Transaction(message: message, socket: self.socket)
            
            self.transactions[tid] = transaction
        } else {
            transaction?.reply = message
            
            transaction?.close()
            
            self.transactions[tid] = nil
        }
    }
}
