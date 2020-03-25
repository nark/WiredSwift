//
//  Message+CoreDataProperties.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//
//

import Foundation
import CoreData


extension Message {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Message> {
        return NSFetchRequest<Message>(entityName: "Message")
    }

    @NSManaged public var body: String?
    @NSManaged public var date: Date?
    @NSManaged public var nick: String?
    @NSManaged public var read: Bool
    @NSManaged public var me: Bool
    @NSManaged public var userID: Int32
    @NSManaged public var conversation: Conversation?

}
