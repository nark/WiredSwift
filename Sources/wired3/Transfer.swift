//
//  Transfer.swift
//  wired3
//
//  Created by Rafael Warnault on 24/04/2021.
//

import Foundation
import WiredSwift

public class Transfer: Equatable {
    public enum TransferType : UInt32 {
        case download = 0
        case upload
    }
    
    public enum TransferState : UInt32 {
        case queued = 0
        case running
    }
    
    var client:Client
    var path:String
    
    var key:String!
    var realDataPath:String!
    var realRsrcPath:String!
    
    var dataFd:FileHandle!
    var rsrcFd:FileHandle!

    var state:TransferState
    var type:TransferType
    var executable:Bool = false
    
    let queueLock = DispatchSemaphore(value: 1)
    let queuePosition:Int = 0
//    var queue_lock
//    var queue
//    var queue_time
    
    var dataOffset:UInt64!
    var rsrcOffset:UInt64!
    var dataSize:UInt64!
    var rsrcSize:UInt64!
    var remainingDataSize:UInt64!
    var remainingRsrcSize:UInt64!
    var transferred:UInt64!
    var actualTransferred:UInt64!
    
//    var speed
//    var finderinfo
    
    public init(path:String, client:Client, message:P7Message, type:TransferType) {
        self.path   = path
        self.client = client
        self.type   = type
        self.state  = .queued
    }
    
    public static func == (lhs: Transfer, rhs: Transfer) -> Bool {
        lhs === rhs
    }
}
