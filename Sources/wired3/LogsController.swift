//
//  LogsController.swift
//  wired3
//
//  Implements the wired.log.* protocol family (spec §10000–10005).
//
//  Architecture (mirrors the original C server wd_server_log_callback):
//    • Conforms to LoggerDelegate and is installed as Logger.delegate on startup.
//    • Every log entry is stored in a thread-safe circular buffer (max 500 entries,
//      trimmed by 100 when the overflow threshold is reached — same policy as the C server).
//    • On each new entry, all clients that have called wired.log.subscribe and hold
//      the wired.account.log.view_log privilege receive a wired.log.message broadcast.
//    • wired.log.get_log replays the buffer as wired.log.list / wired.log.list.done.
//
//  Level mapping (C server: WI_INT32(4 - wi_log_level)):
//    Swift FATAL/ERROR  → wired.log.error   (3)
//    Swift WARNING      → wired.log.warning (2)
//    Swift INFO/NOTICE  → wired.log.info    (1)
//    Swift DEBUG/VERBOSE→ wired.log.debug   (0)

import Foundation
import WiredSwift

public class LogsController: LoggerDelegate {

    // MARK: - Types

    public struct LogEntry {
        public let date: Date
        public let level: Logger.LogLevel
        public let message: String
    }

    // MARK: - Configuration

    /// Maximum number of entries kept in the circular buffer (same default as C server).
    public static let maxEntries = 500

    /// Trim amount when the overflow threshold is exceeded.
    private static let trimAmount = 100

    // MARK: - State

    private var entries: [LogEntry] = []
    private let entriesLock = NSLock()

    // MARK: - Init

    public init() {}

    // MARK: - LoggerDelegate

    public func loggerDidOutput(logger: Logger, output: String) {
        // No-op — we use the structured callback below.
    }

    public func loggerDidLog(level: Logger.LogLevel, message: String, date: Date) {
        let entry = LogEntry(date: date, level: level, message: message)

        // ── Store in circular buffer (same overflow strategy as C server) ──
        entriesLock.lock()
        entries.append(entry)
        let count = entries.count
        if count > Self.maxEntries + Self.trimAmount {
            entries.removeFirst(Self.trimAmount)
        }
        entriesLock.unlock()

        // ── Broadcast to subscribed clients ──
        broadcastEntry(entry)
    }

    // MARK: - Protocol handlers

    /// Handle `wired.log.get_log` — requires `wired.account.log.view_log`.
    public func getLog(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client,
                                            error: "wired.error.message_out_of_sequence",
                                            message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.log.view_log") else {
            App.serverController.replyError(client: client,
                                            error: "wired.error.permission_denied",
                                            message: message)
            return
        }

        // Snapshot the buffer under the lock, then reply outside.
        entriesLock.lock()
        let snapshot = entries
        entriesLock.unlock()

        for entry in snapshot {
            let reply = P7Message(withName: "wired.log.list", spec: client.socket.spec)
            reply.addParameter(field: "wired.log.time", value: entry.date)
            reply.addParameter(field: "wired.log.level", value: wiredLevel(from: entry.level))
            reply.addParameter(field: "wired.log.message", value: entry.message)
            App.serverController.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.log.list.done", spec: client.socket.spec)
        App.serverController.reply(client: client, reply: done, message: message)
    }

    /// Handle `wired.log.subscribe` — requires `wired.account.log.view_log`.
    public func subscribe(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client,
                                            error: "wired.error.message_out_of_sequence",
                                            message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.log.view_log") else {
            App.serverController.replyError(client: client,
                                            error: "wired.error.permission_denied",
                                            message: message)
            return
        }

        if client.isSubscribedToLog {
            App.serverController.replyError(client: client,
                                            error: "wired.error.already_subscribed",
                                            message: message)
            return
        }

        client.isSubscribedToLog = true
        App.serverController.replyOK(client: client, message: message)
    }

    /// Handle `wired.log.unsubscribe` — requires `wired.account.log.view_log`.
    public func unsubscribe(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client,
                                            error: "wired.error.message_out_of_sequence",
                                            message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.log.view_log") else {
            App.serverController.replyError(client: client,
                                            error: "wired.error.permission_denied",
                                            message: message)
            return
        }

        if !client.isSubscribedToLog {
            App.serverController.replyError(client: client,
                                            error: "wired.error.not_subscribed",
                                            message: message)
            return
        }

        client.isSubscribedToLog = false
        App.serverController.replyOK(client: client, message: message)
    }

    // MARK: - Private

    /// Push a new entry to all clients currently subscribed to the log feed.
    private func broadcastEntry(_ entry: LogEntry) {
        // App may not be initialised yet during early startup logging.
        guard let controller = App?.clientsController,
              let serverController = App?.serverController else { return }

        let subscribers = controller.connectedClientsSnapshot().filter {
            $0.state == .LOGGED_IN &&
            $0.isSubscribedToLog &&
            ($0.user?.hasPrivilege(name: "wired.account.log.view_log") == true)
        }

        guard !subscribers.isEmpty else { return }

        for client in subscribers {
            let message = P7Message(withName: "wired.log.message", spec: client.socket.spec)
            message.addParameter(field: "wired.log.time", value: entry.date)
            message.addParameter(field: "wired.log.level", value: wiredLevel(from: entry.level))
            message.addParameter(field: "wired.log.message", value: entry.message)
            _ = serverController.send(message: message, client: client)
        }
    }

    /// Map Swift `Logger.LogLevel` to the protocol `wired.log.level` enum value.
    ///
    /// The C server uses `4 - wi_log_level` where wi_log_level is
    /// FATAL=0, ERROR=1, WARN=2, INFO=3, DEBUG=4.
    /// Equivalent mapping for Swift levels:
    ///
    ///   Swift          → wired.log.level
    ///   FATAL / ERROR  → 3  (wired.log.error)
    ///   WARNING        → 2  (wired.log.warning)
    ///   INFO / NOTICE  → 1  (wired.log.info)
    ///   DEBUG / VERBOSE→ 0  (wired.log.debug)
    private func wiredLevel(from level: Logger.LogLevel) -> UInt32 {
        switch level {
        case .FATAL:   return 3
        case .ERROR:   return 3
        case .WARNING: return 2
        case .INFO:    return 1
        case .NOTICE:  return 1
        case .DEBUG:   return 0
        case .VERBOSE: return 0
        }
    }
}
