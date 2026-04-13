import Foundation
import GRDB

struct TrackedServerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "tracked_servers"

    var id: Int64?
    var source_ip: String
    var display_ip: String
    var port: UInt32
    var url: String
    var category: String
    var is_tracker: Bool
    var name: String
    var description: String
    var users: UInt32
    var files_count: UInt64
    var files_size: UInt64
    var registered_at: Date
    var updated_at: Date?
    var last_seen_at: Date
    var is_active: Bool

    init(trackedServer: TrackerController.TrackedServer) {
        self.id = nil
        self.source_ip = trackedServer.sourceIP
        self.display_ip = trackedServer.displayIP
        self.port = trackedServer.port
        self.url = trackedServer.url
        self.category = trackedServer.category
        self.is_tracker = trackedServer.isTracker
        self.name = trackedServer.name
        self.description = trackedServer.description
        self.users = trackedServer.users
        self.files_count = trackedServer.filesCount
        self.files_size = trackedServer.filesSize
        self.registered_at = trackedServer.registeredAt
        self.updated_at = trackedServer.updatedAt
        self.last_seen_at = trackedServer.lastSeenAt
        self.is_active = trackedServer.isActive
    }

    func trackedServer() -> TrackerController.TrackedServer {
        TrackerController.TrackedServer(
            sourceIP: source_ip,
            displayIP: display_ip,
            port: port,
            url: url,
            category: category,
            isTracker: is_tracker,
            name: name,
            description: description,
            users: users,
            filesCount: files_count,
            filesSize: files_size,
            registeredAt: registered_at,
            updatedAt: updated_at,
            lastSeenAt: last_seen_at,
            isActive: is_active
        )
    }
}
