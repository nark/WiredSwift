import Foundation
import GRDB
import WiredSwift

/// In-memory registry for servers that register against this Wired server acting as a tracker.
final class TrackerController {
    static let entryExpirationInterval: TimeInterval = 360
    private static let purgeInterval: Duration = .seconds(60)

    struct TrackedServer {
        let sourceIP: String
        var displayIP: String
        var port: UInt32
        var url: String
        var category: String
        var isTracker: Bool
        var name: String
        var description: String
        var users: UInt32
        var filesCount: UInt64
        var filesSize: UInt64
        var registeredAt: Date
        var updatedAt: Date?
        var lastSeenAt: Date
        var isActive: Bool
    }

    enum TrackerError: Error {
        case invalidMessage
        case internalError
        case notRegistered
    }

    private var serversBySourceIP: [String: TrackedServer] = [:]
    private let databaseController: DatabaseController
    private let serversLock = Lock()
    private var purgeTask: Task<Void, Never>?

    init(databaseController: DatabaseController) {
        self.databaseController = databaseController
        loadPersistedServers()
        startPurgeLoop()
    }

    deinit {
        stop()
    }

    func stop() {
        purgeTask?.cancel()
        purgeTask = nil
    }

    func replyCategories(to client: Client, message: P7Message, categories: [String], spec: P7Spec) {
        let reply = P7Message(withName: "wired.tracker.categories", spec: spec)
        reply.addParameter(field: "wired.tracker.categories", value: categories)
        App.serverController.reply(client: client, reply: reply, message: message)
    }

    func replyServerList(to client: Client, message: P7Message, spec: P7Spec, now: Date = Date()) {
        purgeExpiredServers(now: now)

        let servers = serversLock.concurrentlyRead {
            serversBySourceIP.values
                .filter { $0.isActive }
                .sorted { lhs, rhs in
                    if lhs.name != rhs.name {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.url.localizedStandardCompare(rhs.url) == .orderedAscending
                }
        }

        for server in servers {
            let reply = P7Message(withName: "wired.tracker.server_list", spec: spec)
            reply.addParameter(field: "wired.tracker.category", value: server.category)
            reply.addParameter(field: "wired.tracker.tracker", value: server.isTracker)
            reply.addParameter(field: "wired.tracker.url", value: server.url)
            reply.addParameter(field: "wired.tracker.users", value: server.users)
            reply.addParameter(field: "wired.info.name", value: server.name)
            reply.addParameter(field: "wired.info.description", value: server.description)
            reply.addParameter(field: "wired.info.files.count", value: server.filesCount)
            reply.addParameter(field: "wired.info.files.size", value: server.filesSize)
            App.serverController.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.tracker.server_list.done", spec: spec)
        App.serverController.reply(client: client, reply: done, message: message)
    }

    func registerServer(client: Client, message: P7Message, allowedCategories: [String], now: Date = Date()) throws -> TrackedServer {
        purgeExpiredServers(now: now)

        guard let sourceIP = normalizedSourceIP(from: client) else {
            throw TrackerError.internalError
        }

        guard let isTracker = message.bool(forField: "wired.tracker.tracker"),
              let rawCategory = message.string(forField: "wired.tracker.category"),
              let port = message.uint32(forField: "wired.tracker.port"),
              let users = message.uint32(forField: "wired.tracker.users"),
              let name = message.string(forField: "wired.info.name"),
              let description = message.string(forField: "wired.info.description"),
              let filesCount = message.uint64(forField: "wired.info.files.count"),
              let filesSize = message.uint64(forField: "wired.info.files.size") else {
            throw TrackerError.invalidMessage
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TrackerError.invalidMessage
        }

        let displayIP = normalizedDisplayIP(from: message, fallback: sourceIP)
        let category = normalizedCategory(rawCategory, allowedCategories: allowedCategories)
        let trackedServer = TrackedServer(
            sourceIP: sourceIP,
            displayIP: displayIP,
            port: port,
            url: trackerURL(displayIP: displayIP, port: port, category: category),
            category: category,
            isTracker: isTracker,
            name: trimmedName,
            description: description,
            users: users,
            filesCount: filesCount,
            filesSize: filesSize,
            registeredAt: now,
            updatedAt: nil,
            lastSeenAt: now,
            isActive: true
        )

        serversLock.exclusivelyWrite {
            serversBySourceIP[sourceIP] = trackedServer
        }
        persist(trackedServer)

        return trackedServer
    }

    func updateServer(client: Client, message: P7Message, now: Date = Date()) throws -> TrackedServer {
        purgeExpiredServers(now: now)

        guard let sourceIP = normalizedSourceIP(from: client) else {
            throw TrackerError.internalError
        }

        guard let users = message.uint32(forField: "wired.tracker.users"),
              let filesCount = message.uint64(forField: "wired.info.files.count"),
              let filesSize = message.uint64(forField: "wired.info.files.size") else {
            throw TrackerError.invalidMessage
        }

        let updatedServer = try serversLock.exclusivelyWrite {
            guard var existing = serversBySourceIP[sourceIP], existing.isActive else {
                throw TrackerError.notRegistered
            }

            existing.users = users
            existing.filesCount = filesCount
            existing.filesSize = filesSize
            existing.updatedAt = now
            existing.lastSeenAt = now
            existing.isActive = true
            serversBySourceIP[sourceIP] = existing
            return existing
        }
        persist(updatedServer)
        return updatedServer
    }

    func purgeExpiredServers(now: Date = Date()) {
        let expiredSourceIPs = serversLock.exclusivelyWrite { () -> [String] in
            var expired: [String] = []
            serversBySourceIP = serversBySourceIP.filter { sourceIP, server in
                let keep = server.isActive && now.timeIntervalSince(server.lastSeenAt) <= Self.entryExpirationInterval
                if !keep {
                    expired.append(sourceIP)
                }
                return keep
            }
            return expired
        }

        if !expiredSourceIPs.isEmpty {
            deletePersisted(sourceIPs: expiredSourceIPs)
        }
    }

    func activeServersSnapshot(now: Date = Date()) -> [TrackedServer] {
        purgeExpiredServers(now: now)
        return serversLock.concurrentlyRead {
            serversBySourceIP.values
                .filter { $0.isActive }
                .sorted { lhs, rhs in
                    if lhs.name != rhs.name {
                        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    }
                    return lhs.url.localizedStandardCompare(rhs.url) == .orderedAscending
                }
        }
    }

    private func startPurgeLoop() {
        purgeTask?.cancel()
        purgeTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: Self.purgeInterval)
                guard !Task.isCancelled else { return }
                self.purgeExpiredServers()
            }
        }
    }

    private func loadPersistedServers(now: Date = Date()) {
        do {
            let records = try databaseController.dbQueue.read { db in
                try TrackedServerRecord.fetchAll(db)
            }

            var activeServers: [String: TrackedServer] = [:]
            var expiredSourceIPs: [String] = []
            for record in records {
                let server = record.trackedServer()
                let isExpired = !server.isActive || now.timeIntervalSince(server.lastSeenAt) > Self.entryExpirationInterval
                if isExpired {
                    expiredSourceIPs.append(server.sourceIP)
                } else {
                    activeServers[server.sourceIP] = server
                }
            }

            serversLock.exclusivelyWrite {
                serversBySourceIP = activeServers
            }

            if !expiredSourceIPs.isEmpty {
                deletePersisted(sourceIPs: expiredSourceIPs)
            }
        } catch {
            Logger.error("TrackerController: failed to load persisted tracker registry: \(error)")
        }
    }

    private func persist(_ server: TrackedServer) {
        do {
            try databaseController.dbQueue.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO tracked_servers (
                        source_ip, display_ip, port, url, category, is_tracker, name, description,
                        users, files_count, files_size, registered_at, updated_at, last_seen_at, is_active
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(source_ip) DO UPDATE SET
                        display_ip = excluded.display_ip,
                        port = excluded.port,
                        url = excluded.url,
                        category = excluded.category,
                        is_tracker = excluded.is_tracker,
                        name = excluded.name,
                        description = excluded.description,
                        users = excluded.users,
                        files_count = excluded.files_count,
                        files_size = excluded.files_size,
                        registered_at = excluded.registered_at,
                        updated_at = excluded.updated_at,
                        last_seen_at = excluded.last_seen_at,
                        is_active = excluded.is_active
                    """,
                    arguments: [
                        server.sourceIP,
                        server.displayIP,
                        Int64(server.port),
                        server.url,
                        server.category,
                        server.isTracker,
                        server.name,
                        server.description,
                        Int64(server.users),
                        Int64(clamping: server.filesCount),
                        Int64(clamping: server.filesSize),
                        server.registeredAt,
                        server.updatedAt,
                        server.lastSeenAt,
                        server.isActive
                    ]
                )
            }
        } catch {
            Logger.error("TrackerController: failed to persist tracked server \(server.sourceIP): \(error)")
        }
    }

    private func deletePersisted(sourceIPs: [String]) {
        do {
            try databaseController.dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM tracked_servers WHERE source_ip IN (\(databaseQuestionMarks(count: sourceIPs.count)))",
                    arguments: StatementArguments(sourceIPs)
                )
            }
        } catch {
            Logger.error("TrackerController: failed to purge persisted tracked servers: \(error)")
        }
    }

    private func databaseQuestionMarks(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private func normalizedSourceIP(from client: Client) -> String? {
        let ip = client.socket.getClientIP() ?? client.ip
        let trimmed = ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizedDisplayIP(from message: P7Message, fallback: String) -> String {
        let override = message.string(forField: "wired.tracker.ip")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return override.isEmpty ? fallback : override
    }

    private func normalizedCategory(_ value: String, allowedCategories: [String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return allowedCategories.contains(trimmed) ? trimmed : ""
    }

    private func trackerURL(displayIP: String, port: UInt32, category: String) -> String {
        let host: String
        if displayIP.contains(":"), !displayIP.hasPrefix("[") {
            host = "[\(displayIP)]"
        } else {
            host = displayIP
        }

        let path = category.isEmpty ? "/" : "/\(category)"
        if port == UInt32(DEFAULT_PORT) {
            return "wired://\(host)\(path)"
        }
        return "wired://\(host):\(port)\(path)"
    }
}
