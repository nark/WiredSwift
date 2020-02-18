//
//  UserCellView.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class UserCellView: NSTableCellView {
    @IBOutlet weak var userNick: NSTextField!
    @IBOutlet weak var userStatus: NSTextField!
    @IBOutlet weak var userIcon: NSImageView!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}
