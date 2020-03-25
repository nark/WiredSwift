//
//  BookmarkViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import KeychainAccess

class BookmarkViewController: NSViewController {
    @IBOutlet weak var nameTextField: NSTextField!
    @IBOutlet weak var addressTextField: NSTextField!
    @IBOutlet weak var loginTextField: NSTextField!
    @IBOutlet weak var passwordTextField: NSTextField!
    @IBOutlet weak var connectAtStartup: NSButton!
    
    public var bookmark: Bookmark!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        if self.bookmark != nil {
            let keychain = Keychain(server: "wired://\(bookmark.hostname!)", protocolType: .irc)

            self.nameTextField.stringValue      = bookmark.name!
            self.addressTextField.stringValue   = bookmark.hostname!
            self.loginTextField.stringValue     = bookmark.login!
            
            if let password = keychain[bookmark.login!] {
                self.passwordTextField.stringValue = password
            }
            
            self.connectAtStartup.state = bookmark.connectAtStartup ? .on : .off
        }
    }
    
    
    @IBAction func cancel(_ sender: Any) {
        NSApp.mainWindow?.windowController?.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.cancel)
    }
    
    @IBAction func ok(_ sender: Any) {
        let keychain        = Keychain(server: "wired://\(bookmark.hostname!)", protocolType: .irc)
        
        bookmark.name       = self.nameTextField.stringValue
        bookmark.hostname   = self.addressTextField.stringValue
        bookmark.login      = self.loginTextField.stringValue
        
        keychain[bookmark.login!] = self.passwordTextField.stringValue
        bookmark.connectAtStartup = self.connectAtStartup.state == .on ? true : false
        
        try? AppDelegate.shared.persistentContainer.viewContext.save()
        
        NSApp.mainWindow?.windowController?.window?.endSheet(self.view.window!, returnCode: NSApplication.ModalResponse.OK)
    }
}
