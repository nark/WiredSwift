//
//  ChatMessageItem.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ChatMessageItem: NSCollectionViewItem {
    @IBOutlet weak var iconView: NSTextField!
    @IBOutlet weak var nickLabel: NSTextField!
    @IBOutlet weak var messageLabel: NSTextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
}
