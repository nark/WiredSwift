//
//  WiredColors.swift
//  Wired
//
//  Created by Rafael Warnault on 29/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


extension NSColor {
    public static func color(forEnum e: UInt32) -> NSColor? {
        switch e {
        case 0:
            return NSColor.black
        case 1:
            return NSColor.red
        case 2:
            return NSColor.orange
        case 3:
            return NSColor.green
        case 4:
            return NSColor.blue
        case 5:
            return NSColor.purple
        default:
            return NSColor.textColor
        }
    }
}
