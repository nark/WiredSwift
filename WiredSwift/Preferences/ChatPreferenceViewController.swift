//
//  AdvancedPreferenceViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import Preferences

final class ChatPreferenceViewController: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier.chat
    let preferencePaneTitle = "Chat"
    let toolbarItemIcon = NSImage(named: "Chat")!

    override var nibName: NSNib.Name? { "ChatPreferenceViewController" }
        
    @IBOutlet weak var eventColorWell: NSColorWell!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let data = UserDefaults.standard.data(forKey: "WSChatEventFontColor"),
              let eventFontColor = try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? NSColor {
            eventColorWell.color = eventFontColor
        }
    }
    
}
