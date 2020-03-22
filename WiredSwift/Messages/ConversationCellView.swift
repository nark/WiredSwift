//
//  UserCellView.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConversationCellView: NSTableCellView {
    @IBOutlet weak var userNick: NSTextField!
    @IBOutlet weak var userDate: NSTextField!
    @IBOutlet weak var userIcon: NSImageView!
    @IBOutlet weak var unreadBadge: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
}
