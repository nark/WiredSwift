import Foundation
import WiredSwift

/// Registers this server with remote trackers listed in `wired.settings.trackers`.
final class OutgoingTrackersController {
    private static let initialDelay: Duration = .seconds(2)
    private static let syncInterval: Duration = .seconds(240)

    private struct TrackerEndpoint: Hashable {
        let rawValue: String
        let host: String
        let port: Int
        let login: String
        let password: String
        let category: String

        var displayName: String {
            port == DEFAULT_PORT ? host : "\(host):\(port)"
        }

        var url: Url {
            var components = URLComponents()
            components.scheme = Wired.wiredScheme
            components.host = host
            components.port = port == DEFAULT_PORT ? nil : port
            components.user = login
            if !password.isEmpty {
                components.password = password
            }
            components.path = category.isEmpty ? "/" : "/\(category)"
            return Url(withString: components.string ?? "wired://\(displayName)/")
        }
    }

    private struct TrackerPayload {
        let isTracker: Bool
        let port: UInt32
        let users: UInt32
        let name: String
        let description: String
        let filesCount: UInt64
        let filesSize: UInt64
    }

    private let stateLock = Lock()
    private var syncTask: Task<Void, Never>?
    private var hasRegisteredTracker: Set<String> = []

    func start() {
        restartLoop(resetRegistrations: true)
    }

    func stop() {
        stateLock.exclusivelyWrite {
            syncTask?.cancel()
            syncTask = nil
            hasRegisteredTracker.removeAll()
        }
    }

    func refreshConfiguration(resetRegistrations: Bool = true) {
        restartLoop(resetRegistrations: resetRegistrations)
    }

    private func restartLoop(resetRegistrations: Bool) {
        stateLock.exclusivelyWrite {
            syncTask?.cancel()
            syncTask = nil
            if resetRegistrations {
                hasRegisteredTracker.removeAll()
            }

            syncTask = Task.detached(priority: .background) { [weak self] in
                guard let self else { return }

                try? await Task.sleep(for: Self.initialDelay)
                guard !Task.isCancelled else { return }

                while !Task.isCancelled {
                    await self.syncAllTrackers()
                    try? await Task.sleep(for: Self.syncInterval)
                }
            }
        }
    }

    private func syncAllTrackers() async {
        guard App.serverController.registerWithTrackers else { return }

        let endpoints = App.serverController.trackers.compactMap(parseEndpoint(from:))
        guard !endpoints.isEmpty else { return }

        for endpoint in endpoints {
            guard !Task.isCancelled else { return }
            await sync(endpoint: endpoint)
        }
    }

    private func sync(endpoint: TrackerEndpoint) async {
        let connection = AsyncConnection(withSpec: App.serverController.spec)

        do {
            try connection.connect(
                withUrl: endpoint.url,
                cipher: .ECDH_CHACHA20_POLY1305,
                compression: .LZ4,
                checksum: .HMAC_256
            )
            defer { connection.disconnect() }

            let shouldTryUpdate = stateLock.concurrentlyRead {
                hasRegisteredTracker.contains(endpoint.rawValue)
            }

            if shouldTryUpdate {
                do {
                    try await sendUpdate(to: connection)
                    Logger.debug("Updated tracker registration for \(endpoint.displayName)")
                    return
                } catch let AsyncConnectionError.serverError(message)
                    where isNotRegisteredError(message) {
                    Logger.info("Tracker \(endpoint.displayName) forgot this server; registering again")
                } catch {
                    Logger.warning("Tracker update failed for \(endpoint.displayName): \(error.localizedDescription)")
                }
            }

            try await sendRegister(to: connection, endpoint: endpoint)
            stateLock.exclusivelyWrite {
                hasRegisteredTracker.insert(endpoint.rawValue)
            }
            Logger.info("Registered this server with tracker \(endpoint.displayName)")
        } catch {
            Logger.warning("Tracker sync failed for \(endpoint.displayName): \(error.localizedDescription)")
            stateLock.exclusivelyWrite {
                hasRegisteredTracker.remove(endpoint.rawValue)
            }
        }
    }

    private func sendRegister(to connection: AsyncConnection, endpoint: TrackerEndpoint) async throws {
        let message = P7Message(withName: "wired.tracker.send_register", spec: App.serverController.spec)
        let payload = currentPayload()

        message.addParameter(field: "wired.tracker.tracker", value: payload.isTracker)
        message.addParameter(field: "wired.tracker.category", value: endpoint.category)
        message.addParameter(field: "wired.tracker.port", value: payload.port)
        message.addParameter(field: "wired.tracker.users", value: payload.users)
        message.addParameter(field: "wired.info.name", value: payload.name)
        message.addParameter(field: "wired.info.description", value: payload.description)
        message.addParameter(field: "wired.info.files.count", value: payload.filesCount)
        message.addParameter(field: "wired.info.files.size", value: payload.filesSize)

        let reply = try await connection.sendAsync(message)
        guard reply?.name == "wired.okay" else {
            throw AsyncConnectionError.writeFailed
        }
    }

    private func sendUpdate(to connection: AsyncConnection) async throws {
        let payload = currentPayload()
        let message = P7Message(withName: "wired.tracker.send_update", spec: App.serverController.spec)
        message.addParameter(field: "wired.tracker.users", value: payload.users)
        message.addParameter(field: "wired.info.files.count", value: payload.filesCount)
        message.addParameter(field: "wired.info.files.size", value: payload.filesSize)

        let reply = try await connection.sendAsync(message)
        guard reply?.name == "wired.okay" else {
            throw AsyncConnectionError.writeFailed
        }
    }

    private func parseEndpoint(from rawValue: String) -> TrackerEndpoint? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.contains("://") ? trimmed : "wired://\(trimmed)"
        guard let components = URLComponents(string: normalized),
              let host = components.host,
              !host.isEmpty else {
            Logger.warning("Ignoring invalid tracker URL '\(rawValue)'")
            return nil
        }

        let login = (components.user?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? components.user!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "guest"

        let category = components.path
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        return TrackerEndpoint(
            rawValue: trimmed,
            host: host,
            port: components.port ?? DEFAULT_PORT,
            login: login,
            password: components.password ?? "",
            category: category
        )
    }

    private func isNotRegisteredError(_ message: P7Message) -> Bool {
        let errorString = message.string(forField: "wired.error.string")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return errorString == "wired.error.not_registered" || errorString == "not_registered"
    }

    private func currentPayload() -> TrackerPayload {
        let users = UInt32(clamping: App.clientsController.connectedClientsSnapshot().filter {
            $0.state == .LOGGED_IN
        }.count)

        return TrackerPayload(
            isTracker: App.serverController.trackerEnabled,
            port: UInt32(clamping: App.serverController.port),
            users: users,
            name: App.serverController.serverName,
            description: App.serverController.serverDescription,
            filesCount: App.indexController.totalFilesCount,
            filesSize: App.indexController.totalFilesSize
        )
    }
}
