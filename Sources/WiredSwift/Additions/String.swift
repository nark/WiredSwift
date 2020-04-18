//
//  String.swift
//  Wired
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation


extension String {
    public var nullTerminated: Data? {
        if var data = self.data(using: String.Encoding.utf8) {
            data.append(0)
            return data
        }
        return nil
    }
    
    public func deletingPrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }

    
    public var isBlank: Bool {
        return allSatisfy({ $0.isWhitespace })
    }
}

extension Optional where Wrapped == String {
  public var isBlank: Bool {
    return self?.isBlank ?? true
  }
}
