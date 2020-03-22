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
}
