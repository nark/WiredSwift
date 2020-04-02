//
//  WiredColors.swift
//  Wired
//
//  Created by Rafael Warnault on 29/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


enum InterfaceStyle : String {
    case Dark, Light
    init() {
      let type = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"
      self = InterfaceStyle(rawValue: type)!
    }
}
let currentStyle = InterfaceStyle()


extension NSColor {
    public static func color(forEnum e: UInt32) -> NSColor? {
        switch e {
        case 0:
        if currentStyle.rawValue == "Light" {
            return NSColor.black
        } else {
            return NSColor.white
        }
        case 1:
        if currentStyle.rawValue == "Light" {
            return NSColor.red
        } else {
            return NSColor(hue: 0, saturation: 0.63, brightness: 0.84, alpha: 1)
        }
        case 2:
            return NSColor.orange
        case 3:
            return NSColor.green
        case 4:
        if currentStyle.rawValue == "Light" {
            return NSColor.blue
        } else {
            return NSColor(hue: 218, saturation: 0.43, brightness: 0.94, alpha: 1)
        }
        case 5:
            return NSColor.purple
        default:
            return NSColor.textColor
        }
    }
}
