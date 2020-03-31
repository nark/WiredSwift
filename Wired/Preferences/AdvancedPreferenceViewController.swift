//
//  AdvancedPreferenceViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import Preferences

final class AdvancedPreferenceViewController: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier.advanced
    let preferencePaneTitle = NSLocalizedString("Advanced", comment: "")
  
    
    let toolbarItemIcon = NSImage(named: NSImage.advancedName)!

    override var nibName: NSNib.Name? { "AdvancedPreferenceViewController" }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup stuff here
    }
}
