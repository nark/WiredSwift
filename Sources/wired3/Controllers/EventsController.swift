import Foundation
import GRDB
import WiredSwift

/// Persists and queries server event log entries in the GRDB database.
///
/// Events are written via `addEvent` and can be retrieved with `listEvents`.
/// The `deleteEvents` method supports range-based pruning of old entries.
public final class EventsController {
    enum RetentionPolicy: String, Equatable {
        case never
        case daily
        case weekly
        case monthly
        case yearly

        var maxAge: TimeInterval? {
            switch self {
            case .never:
                return nil
            case .daily:
                return 24 * 3600
            case .weekly:
                return 7 * 24 * 3600
            case .monthly:
                return 31 * 24 * 3600
            case .yearly:
                return 365 * 24 * 3600
            }
        }

        static func parse(_ rawValue: String?) -> RetentionPolicy {
            guard let rawValue else { return .never }

            switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "never", "none":
                return .never
            case "daily":
                return .daily
            case "weekly":
                return .weekly
            case "monthly":
                return .monthly
            case "yearly":
                return .yearly
            default:
                return .never
            }
        }
    }

    private let databaseController: DatabaseController
    private let maintenanceQueue = DispatchQueue(label: "wired3.events.maintenance")
    private var purgeTimer: DispatchSourceTimer?
    private var retentionPolicy: RetentionPolicy = .never
    private var lastPurgeDate: Date?
    private let minimumPurgeSpacing: TimeInterval = 300

    init(databaseController: DatabaseController) {
        self.databaseController = databaseController
    }

    deinit {
        purgeTimer?.cancel()
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
        purgeExpiredEventsIfNeeded()

        return try databaseController.dbQueue.write { db in
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

    func configureAutoPurge(retentionPolicy: RetentionPolicy) {
        maintenanceQueue.async { [weak self] in
            guard let self else { return }
            self.retentionPolicy = retentionPolicy
            self.purgeTimer?.cancel()
            self.purgeTimer = nil

            guard retentionPolicy != .never else { return }

            let timer = DispatchSource.makeTimerSource(queue: self.maintenanceQueue)
            timer.schedule(deadline: .now() + 60, repeating: 3600)
            timer.setEventHandler { [weak self] in
                self?.purgeExpiredEvents(force: false)
            }
            self.purgeTimer = timer
            timer.resume()

            self.purgeExpiredEvents(force: true)
        }
    }

    func purgeExpiredEventsIfNeeded() {
        maintenanceQueue.async { [weak self] in
            self?.purgeExpiredEvents(force: false)
        }
    }

    private func purgeExpiredEvents(force: Bool) {
        guard let maxAge = retentionPolicy.maxAge else { return }
        let now = Date()

        if !force, let lastPurgeDate, now.timeIntervalSince(lastPurgeDate) < minimumPurgeSpacing {
            return
        }

        let cutoffDate = now.addingTimeInterval(-maxAge)

        do {
            try databaseController.dbQueue.write { db in
                try EventEntry
                    .filter(EventEntry.Columns.time <= cutoffDate)
                    .deleteAll(db)
            }
            lastPurgeDate = now
        } catch {
            Logger.error("Failed to purge expired events: \(error)")
        }
    }
}
