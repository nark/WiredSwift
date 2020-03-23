//
//  AdvancedPreferenceViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import Preferences

final class ChatPreferenceViewController: NSViewController, PreferencePane, NSTableViewDelegate, NSTableViewDataSource {
    let preferencePaneIdentifier = PreferencePane.Identifier.chat
    let preferencePaneTitle = "Chat"
    let toolbarItemIcon = NSImage(named: "Chat")!

    override var nibName: NSNib.Name? { "ChatPreferenceViewController" }
        
    @IBOutlet weak var substitutionsTableView: NSTableView!
    
    var substitutionKeys:[String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        self.reload()
    }
    
    private func reload() {
        if let dict = UserDefaults.standard.object(forKey: "WSEmojiSubstitutions") as? [String:String] {
            self.substitutionKeys = dict.keys.sorted()
        }
    }
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.substitutionKeys.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        
        if tableColumn!.identifier.rawValue == "key" {
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "KeyCell"), owner: self) as? NSTableCellView
            view?.textField?.stringValue = self.substitutionKeys[row]
            
        } else if tableColumn!.identifier.rawValue == "emoji" {
            if let dict = UserDefaults.standard.object(forKey: "WSEmojiSubstitutions") as? [String:String] {
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "EmojiCell"), owner: self) as? NSTableCellView
                if let emoji = dict[self.substitutionKeys[row]] {
                    view?.textField?.stringValue = emoji
                }
            }
        }

        return view
    }
}
