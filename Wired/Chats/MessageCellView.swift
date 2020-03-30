//
//  MessageCellView.swift
//  Wired
//
//  Created by Rafael Warnault on 30/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class MessageCellView: NSTableCellView {
    @IBOutlet weak var nickLabel: NSTextField!
    @IBOutlet weak var timeLabel: NSTextField!
    @IBOutlet weak var userIcon: NSImageView!
}
