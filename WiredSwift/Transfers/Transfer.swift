//
//  Transfer.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

public class Transfer: ConnectionObject {
    enum State {
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
    
    let state:State!
    let identifier:String!
    
    public override init(_ connection: Connection) {
        self.state = .Waiting
        self.identifier = UUID().uuidString
            
        super.init(connection)
    }
}


public class DownloadTransfer : Transfer {
    
}


public class UploadTransfer : Transfer {
    
}
