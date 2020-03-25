//
//  Bookmark+CoreDataProperties.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 18/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//
//

import Foundation
import CoreData


extension Bookmark {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Bookmark> {
        return NSFetchRequest<Bookmark>(entityName: "Bookmark")
    }

    @NSManaged public var name: String?
    @NSManaged public var hostname: String?
    @NSManaged public var login: String?
    @NSManaged public var nick: String?
    @NSManaged public var status: String?
    @NSManaged public var connectAtStartup: Bool
}
