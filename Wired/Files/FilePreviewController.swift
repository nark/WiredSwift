//
//  FilePreviewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 24/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class FilePreviewController: NSViewController {
    @IBOutlet weak var iconView: NSImageView!
    @IBOutlet weak var filenameLabel: NSTextField!
    @IBOutlet weak var sizeLabel: NSTextField!
    @IBOutlet weak var typeLabel: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
    }
}
