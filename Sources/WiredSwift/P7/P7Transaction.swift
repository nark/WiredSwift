//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/05/2021.
//

import Foundation
import NIO

public class P7Transaction {
    public var transactionID:UInt32? = nil
    public var socket:P7Socket
    public var originator:Originator
    public var message:P7Message
    public var reply:P7Message?
    
    public var specTransaction:P7SpecTransaction? = nil
    public var state:State
    
    public var lock:DispatchSemaphore? = nil
    
    public enum State: Int {
        case pending        = 0
        case terminated
    }
    
    public init?(message:P7Message, socket:P7Socket) {
        guard let transaction = message.uint32(forField: "wired.transaction") else {
            return nil
        }
        self.socket             = socket
        self.message            = message
        self.originator         = socket.originator
        self.specTransaction    = socket.spec.transactionsByName[message.name]
        self.transactionID      = transaction
        self.state              = .pending
        
        self.lock               = DispatchSemaphore(value: 0)
    }
    
    
    public func send(channel:Channel) -> Bool {
        return self.socket.write(self.message, channel: channel)
    }
    
    public func wait() {
        print("wait")
        self.lock?.wait()
    }
    
    
    public func close() {
        print("release")
        self.lock?.signal()
    }
}
