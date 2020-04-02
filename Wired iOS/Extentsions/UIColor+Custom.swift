//
//  UIColor+Custom.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 02/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit

extension UIColor {
    static var incomingGray: UIColor {
        if #available(iOS 13, *) {
            return UIColor.systemGray5
        } else {
            return UIColor(red: 230/255, green: 230/255, blue: 235/255, alpha: 1.0)
        }
    }


    static var outgoingGreen: UIColor {
        if #available(iOS 13, *) {
            return UIColor.systemGreen
        } else {
            return UIColor(red: 69/255, green: 214/255, blue: 93/255, alpha: 1.0)
        }
    }
}
