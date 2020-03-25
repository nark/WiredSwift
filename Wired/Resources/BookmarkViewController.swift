//
//  BookmarkViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class BookmarkViewController: NSViewController {
    public var bookmark: Bookmark!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
    
    
    @IBAction func cancel(_ sender: Any) {
        NSApp.mainWindow?.windowController?.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.cancel)
    }
    
    @IBAction func ok(_ sender: Any) {
        NSApp.mainWindow?.windowController?.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.OK)
    }
}
