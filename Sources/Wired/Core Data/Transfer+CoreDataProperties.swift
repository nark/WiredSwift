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
    @objc public enum State: Int32, CustomStringConvertible {
        public var description: String {
          switch self {
          case .Waiting:
            let Waiting = NSLocalizedString("Waiting", comment: "")
            return Waiting
          case .LocallyQueued:
            let LocallyQueued = NSLocalizedString("LocallyQueued", comment: "")
            return LocallyQueued
          case .Queued:
            let Queued = NSLocalizedString("Queued", comment: "")
            return Queued
          case .Listing:
            let Listing = NSLocalizedString("Listing", comment: "")
            return Listing
          case .CreatingDirectories:
            let CreatingDirectories = NSLocalizedString("CreatingDirectories", comment: "")
            return CreatingDirectories
          case .Running:
            let Running = NSLocalizedString("Running", comment: "")
            return Running
          case .Pausing:
            let Pausing = NSLocalizedString("Pausing", comment: "")
            return Pausing
          case .Paused:
            let Paused = NSLocalizedString("Paused", comment: "")
            return Paused
          case .Stopping:
            let Stopping = NSLocalizedString("Stopping", comment: "")
            return Stopping
          case .Stopped:
            let Stopped = NSLocalizedString("Stopped", comment: "")
            return Stopped
          case .Disconnecting:
            let Disconnecting = NSLocalizedString("Disconnecting", comment: "")
            return Disconnecting
          case .Disconnected:
            let Disconnected = NSLocalizedString("Disconnected", comment: "")
            return Disconnected
          case .Removing:
            let Removing = NSLocalizedString("Removing", comment: "")
            return Removing
          case .Finished:
            let Finished = NSLocalizedString("Finished", comment: "")
            return Finished
            }
        }
        
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
    @NSManaged public var name: String?
    @NSManaged public var identifier: UUID?
    @NSManaged public var uri: String?
    @NSManaged public var isFolder: Bool
    @NSManaged public var localPath: String?
    @NSManaged public var remotePath: String?
    @NSManaged public var dataTransferred: Int64
    @NSManaged public var rsrcTransferred: Int64
    @NSManaged public var actualTransferred: Int64
    @NSManaged public var startDate: Date?
    @NSManaged public var accumulatedTime: Double
    @NSManaged public var percent: Double
    @NSManaged public var speed: Double
    @NSManaged public var size: Int64
}
