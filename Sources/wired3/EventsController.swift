import Foundation
import GRDB
import WiredSwift

/// Persists and queries server event log entries in the GRDB database.
///
/// Events are written via `addEvent` and can be retrieved with `listEvents`.
/// The `deleteEvents` method supports range-based pruning of old entries.
public final class EventsController {
    private let databaseController: DatabaseController

    init(databaseController: DatabaseController) {
        self.databaseController = databaseController
    }

    func firstEventDate() throws -> Date? {
        try databaseController.dbQueue.read { db in
            try EventEntry
                .order(EventEntry.Columns.time.asc)
                .fetchOne(db)?
                .time
        }
    }

    func listEvents(
        from fromTime: Date?,
        numberOfDays: UInt32,
        lastEventCount: UInt32
    ) throws -> [EventEntry] {
        try databaseController.dbQueue.read { db in
            if let fromTime {
                var request = EventEntry
                    .filter(EventEntry.Columns.time >= fromTime)
                    .order(EventEntry.Columns.time.asc)

                if numberOfDays > 0 {
                    let endDate = fromTime.addingTimeInterval(TimeInterval(numberOfDays) * 24 * 3600)
                    request = request.filter(EventEntry.Columns.time <= endDate)
                }

                return try request.fetchAll(db)
            }

            let limit = max(Int(lastEventCount), 0)
            guard limit > 0 else { return [] }

            return try EventEntry
                .order(EventEntry.Columns.time.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    @discardableResult
    func addEvent(
        _ event: WiredServerEvent,
        parameters: [String],
        nick: String,
        login: String,
        ip: String
    ) throws -> EventEntry {
        try databaseController.dbQueue.write { db in
            let entry = EventEntry(
                eventCode: event.rawValue,
                parameters: parameters,
                nick: nick,
                login: login,
                ip: ip
            )
            try entry.insert(db)
            return entry
        }
    }

    func deleteEvents(from fromTime: Date?, to toTime: Date?) throws {
        try databaseController.dbQueue.write { db in
            var request = EventEntry.all()

            if let fromTime {
                request = request.filter(EventEntry.Columns.time >= fromTime)
            }

            if let toTime {
                request = request.filter(EventEntry.Columns.time <= toTime)
            }

            try request.deleteAll(db)
        }
    }
}
