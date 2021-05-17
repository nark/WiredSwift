//
//  P7TransactionHandler.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 16/05/2021.
//

import Foundation
import NIO

public class P7TransactionHandler {
    private var socket:P7Socket!
    
    internal var transactionSemaphore:DispatchSemaphore? = nil
    internal var transactionMessage:P7Message? = nil
    internal var currentTransaction:P7SpecTransaction? = nil
    internal var transactionID:UInt32 = 0
    
    public init(socket:P7Socket) {
        self.socket = socket
    }
    
    
    public func send(message: P7Message, channel: Channel) -> P7Message? {
        self.currentTransaction = self.socket.spec.transactionsByName[message.name]
                
        if self.currentTransaction != nil {
            self.transactionSemaphore = DispatchSemaphore(value: 0)
        }
        
        if let t = message.uint32(forField: "wired.transaction") {
            self.transactionID = t
        } else {
            self.transactionID += 1
            
            message.addParameter(field: "wired.transaction", value: self.transactionID)
        }
        
        self.transactionMessage = nil
        
        _ = self.socket.write(message, channel: channel)
        
        if self.currentTransaction != nil {
            self.transactionSemaphore?.wait()
        }
        
        return self.transactionMessage
    }
    
    
    
    public func receive(message: P7Message) {
        print("receive \(message.name!)")
        if let transaction = message.uint32(forField: "wired.transaction") {

            if self.currentTransaction == nil {
                Logger.debug("Unknow transaction, skip")
                
                self.transactionMessage = nil
                self.transactionSemaphore = nil
                
                self.transactionSemaphore?.signal()
                
                return
            }
            
            if transaction != self.transactionID {
                Logger.error("Wrong transaction (\(transaction)), expected (\(self.transactionID)), abort")
                
                self.transactionMessage = nil
                self.transactionSemaphore = nil
                
                self.transactionSemaphore?.signal()
                
                return
            }
            
            if self.currentTransaction!.verify(candidate: message) {
                self.transactionMessage = message
            } else {
                Logger.error("Wrong message candidate (\(message.name!)) for transaction (\(self.currentTransaction!.name!)), return nil")
                
                self.transactionMessage = nil
            }
            
            self.transactionSemaphore?.signal()
        }
    }
}
