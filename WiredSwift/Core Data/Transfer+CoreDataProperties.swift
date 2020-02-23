//
//  Transfer+CoreDataProperties.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 22/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//
//

import Foundation
import CoreData


extension Transfer {
    @objc public enum State: Int32 {
        case Waiting
        case LocallyQueued
        case Queued
        case Listing
        case CreatingDirectories
        case Running
        case Pausing
        case Paused
        case Stopping
        case Stopped
        case Disconnecting
        case Disconnected
        case Removing
        case Finished
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Transfer> {
        return NSFetchRequest<Transfer>(entityName: "Transfer")
    }

    @NSManaged public var state: State
    @NSManaged public var identifier: UUID?
    @NSManaged public var isFolder: Bool
    @NSManaged public var localPath: String?
    @NSManaged public var remotePath: String?
    @NSManaged public var dataTransferred: Int64
    @NSManaged public var rsrcTransferred: Int64
    @NSManaged public var actualTransferred: Int64
    @NSManaged public var startDate: Date?
    @NSManaged public var accumulatedTime: Double
    @NSManaged public var percent: Float

}
