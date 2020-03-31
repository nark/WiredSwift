//
//  AdvancedPreferenceViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa
import Preferences

final class FilesPreferenceViewController: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier.files
    let preferencePaneTitle = NSLocalizedString("Files", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.folderName)!

    override var nibName: NSNib.Name? { "FilesPreferenceViewController" }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup stuff here
    }
}
