//
//  Conversation+CoreDataClass.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//
//

import Foundation
import CoreData

@objc(Conversation)
public class Conversation: NSManagedObject {
    public var connection:Connection!
    public var userID:UInt32!
    
    public func unreads() -> Int {
        var count = 0
        
        for m in self.messages! {
            if let message = m as? Message {
                if message.read == false {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    
    public func markAllAsRead() -> Int {
        var count = 0
        
        for m in self.messages! {
            if let message = m as? Message {
                if message.read == false {
                    message.read = true
                    count += 1
                }
            }
        }
        
        return 0
    }
}
