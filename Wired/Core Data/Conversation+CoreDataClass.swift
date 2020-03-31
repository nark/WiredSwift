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
    public var connection:ServerConnection!
    
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
    
    
    public func lastMessageTime() -> String? {
        if let last = self.messages?.lastObject as? Message {
            if let date = last.date {
                let elapsed = Int(Date().timeIntervalSince(date))
                
                if elapsed > 3600 * 24 {
                    return AppDelegate.dateTimeFormatter.string(from: date)
                } else {
                    return timeAgoSince(date)
                }
            }
        }
        return nil
    }
}
