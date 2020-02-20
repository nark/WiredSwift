//
//  TransfersController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class TransfersController {
    public static let shared = TransfersController()
    
    var transfers:[Transfer] = []
    
    private init() {

    }
    
        
    public func download(_ file:File, toPath:String) -> Bool {
        return true
    }
    
    public func upload(_ path:String, toFile:File) -> Bool {
        return true
    }
}
