//
//  UnselectedTableRowView.swift
//  Wired
//
//  Created by Rafael Warnault on 02/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

public class UnselectedTableRowView: NSTableRowView {
    public override func drawSelection(in dirtyRect: NSRect) { }
    public override var isEmphasized: Bool {
        set {}
        get {
            return false
        }
    }
}
