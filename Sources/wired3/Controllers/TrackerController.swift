import Foundation
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
    private let serversLock = Lock()
    private var purgeTask: Task<Void, Never>?

    init() {
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

        return try serversLock.exclusivelyWrite {
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
    }

    func purgeExpiredServers(now: Date = Date()) {
        serversLock.exclusivelyWrite {
            serversBySourceIP = serversBySourceIP.filter { _, server in
                guard server.isActive else { return false }
                return now.timeIntervalSince(server.lastSeenAt) <= Self.entryExpirationInterval
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
