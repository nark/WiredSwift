//
//  FilesController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa


public class FilesController: ConnectionObject {
    var rootFile:File!
    
    public override init(_ connection: Connection) {
        super.init(connection)
        
        self.rootFile = File("/", connection: connection)
    }
    
    public convenience init(withRoot root: String, connection: Connection) {
        self.init(connection)
                
        self.rootFile = File(root, connection: connection)
    }
    
    public func load(ofFile file:File?) {
        if let f = file {
            f.load()
        } else {
            rootFile.load()
        }
    }
}
