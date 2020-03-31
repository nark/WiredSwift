//
//  AttributedString.swift
//  Wired
//
//  Created by Rafael Warnault on 30/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation


extension String {
    func substituteURL() -> NSAttributedString? {
        let resultString = NSMutableAttributedString(string: self)
        
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))

        for match in matches {
            guard let range = Range(match.range, in: self) else { continue }
            let url = self[range]
            
            resultString.addAttributes([NSAttributedString.Key.link: url], range: NSRange(range, in: self))
        }
        
        return resultString
    }
}
