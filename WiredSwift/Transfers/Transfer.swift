//
//  Transfer.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class Transfer: ConnectionObject {
    public var transferConnection: TransferConnection?
    
    public enum State {
        case Waiting
        case LocallyQueued
        case Queued
        case Listing
        case CreatingDirectories
        case Running
        case Pausing
        case Paused
        case Stopping
        case Stopped
        case Disconnecting
        case Disconnected
        case Removing
        case Finished
    }

    public var identifier:String = UUID().uuidString
    public var state:Transfer.State = .Waiting
    public var isFolder:Bool = false
    
    public var file:File?
    public var localPath:String?
    public var remotePath:String?
    
    
    public  override init(_ connection: Connection) {
        super.init(connection)
    }
    
    
    
    public func isWorking() -> Bool {
        return (state == .Waiting || state == .Queued ||
                state == .Listing || state == .CreatingDirectories ||
                state == .Running)
    }

    public func isTerminating() -> Bool {
        return (state == .Pausing || state == .Stopping ||
            state == .Disconnecting || state == .Removing)
    }

    public func isStopped() -> Bool {
        return (state == .Paused || state == .Stopped ||
                state == .Disconnected || state == .Finished)
    }
}


public class DownloadTransfer : Transfer {
    
}


public class UploadTransfer : Transfer {
    
}
