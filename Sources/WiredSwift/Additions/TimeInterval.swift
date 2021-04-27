//
//  TimeInterval.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/04/2021.
//

import Foundation

public extension TimeInterval {
    func stringFromTimeInterval() -> String {
        var result  = ""
        var past    = false
        
        if self < 0 {
            past = true
        }
        
        let ti      = NSInteger(self)
        let seconds = ti % 60
        let minutes = (ti / 60) % 60
        let hours   = (ti / 3600)
        let days    = (ti / 86400)
        
        if(days > 0) {
            result  = String(format: "%0.2d:%0.2d:%0.2d:%0.2d days", days, hours, minutes, seconds)
        }
        else if(hours > 0) {
            result  = String(format: "%0.2d:%0.2d:%0.2d hours", hours, minutes, seconds)
        }
        else if(minutes > 0) {
            result  = String(format: "%0.2d:%0.2d minutes", minutes, seconds)
        }
        else {
            result  = String(format: "%0.2d:%0.2d seconds", minutes, seconds)
        }
        
        if past {
            result  = String(format: "%@ ago", result)
        }
        
        return result
    }
}
