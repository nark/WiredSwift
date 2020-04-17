//
//  ConnectionWindow.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConnectionWindow: NSWindow {
    override func close() {
        if let cwc = self.windowController as? ConnectionWindowController {
            if cwc.connection != nil && cwc.connection.isConnected() {
                if UserDefaults.standard.bool(forKey: "WSCheckActiveConnectionsBeforeQuit") == true {
                    let alert = NSAlert()
                    alert.messageText = NSLocalizedString("Are you sure you want to disconnect?", comment: "")
                    alert.informativeText = NSLocalizedString("Every running transfers may be stopped", comment: "")
                    alert.alertStyle = .warning
                    let YesButtonText = NSLocalizedString("Yes", comment: "")
                    alert.addButton(withTitle: YesButtonText)
                    let CancelButtonText = NSLocalizedString("Cancel", comment: "")
                    alert.addButton(withTitle: CancelButtonText)
                    
                    alert.beginSheetModal(for: self) { (modalResponse: NSApplication.ModalResponse) -> Void in
                        if modalResponse == .alertFirstButtonReturn {
                            cwc.disconnect()
                            super.close()
                        }
                    }
                } else {
                    cwc.disconnect()
                    super.close()
                }
            } else {
                super.close()
            }
        } else {
            super.close()
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}
