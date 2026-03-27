//
//  AppController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

public let DEFAULT_PORT = 4871
private let defaultWelcomeBoardPath = "Welcome"
private let defaultWelcomeThreadSubject = "Welcome to Wired Server 3"
private let defaultWelcomeThreadBody = "You are running Wired Server version 3.x, this is an early alpha version, you are pleased to report any issue at : https://github.com/nark/WiredSwift/issues"
private let welcomeBoardSeed = "boards.welcome.v1"
private let defaultFilesSeed = "files.defaults.v1"

public class AppController {
    var workingDirectoryPath: String
    var rootPath: String
    var configPath: String

    var spec: P7Spec!

    var serverController: ServerController!

    var databaseURL: URL!
    var databaseController: DatabaseController!
    var clientsController: ClientsController!
    var usersController: UsersController!
    var chatsController: ChatsController!
    var banListController: BanListController!
    var eventsController: EventsController!
    var boardsController: BoardsController!
    var filesController: FilesController!
    public var indexController: IndexController!
    var transfersController: TransfersController!
    var bootstrapStateStore: BootstrapStateStore!
    var logsController: LogsController!

    var config: Config

    /// When true (--debug flag), log level is pinned to DEBUG and SIGHUP cannot lower it.
    public var debugMode: Bool = false

    // MARK: - Public
    public init(specPath: String, dbPath: String, rootPath: String, configPath: String, workingDirectoryPath: String, debugMode: Bool = false) {
        let specUrl = URL(fileURLWithPath: specPath)

        self.workingDirectoryPath = workingDirectoryPath
        self.rootPath = rootPath
        self.configPath = configPath
        self.databaseURL = URL(fileURLWithPath: dbPath)
        self.config = Config(withPath: configPath)
        self.debugMode = debugMode

        if !self.config.load() {
            Logger.fatal("Cannot load config file at path \(configPath)")
            exit(-1)
        }

        if let spec = P7Spec(withUrl: specUrl) {
            self.spec = spec
        } else {
            Logger.fatal("Cannot load spec file at path \(specPath)")
            exit(-1)
        }
    }

    public func start() {
        // Install LogsController as Logger.delegate first so that every log
        // emitted during startup is captured in the buffer and can be
        // replayed via wired.log.get_log once a client subscribes.
        self.logsController = LogsController()
        Logger.delegate = self.logsController

        self.bootstrapStateStore = BootstrapStateStore(workingDirectoryPath: self.workingDirectoryPath)
        self.databaseController = DatabaseController(baseURL: self.databaseURL, spec: self.spec)

        // Open the database and run pending migrations FIRST so that dbQueue
        // is valid before any controller that queries it (e.g. IndexController
        // calls detectFTS5() in its init via dbQueue.read).
        if !self.databaseController.initDatabase() {
            Logger.error("Error while initializing database")
        }

        self.clientsController = ClientsController()
        self.filesController = FilesController(rootPath: self.rootPath)
        self.usersController = UsersController(databaseController: self.databaseController)
        self.chatsController = ChatsController(databaseController: self.databaseController)
        self.banListController = BanListController(databaseController: self.databaseController)
        self.eventsController = EventsController(databaseController: self.databaseController)
        self.boardsController = BoardsController(databasePath: self.databaseURL.path)
        self.indexController = IndexController(databaseController: self.databaseController,
                                               filesController: self.filesController)

        self.transfersController = TransfersController(filesController: filesController)

        // Seed initial data (only on first run — no-op if data already exists)
        self.usersController.seedDefaultDataIfNeeded()
        self.chatsController.seedDefaultDataIfNeeded()

        // Legacy schema migrations (no-op on fresh GRDB databases)
        self.usersController.migrateLegacyPrivilegesSchemaIfNeeded()
        self.usersController.backfillStableIdentitiesIfNeeded()

        self.chatsController.loadChats()
        self.bootstrapDefaultContentIfNeeded()

        if !self.indexController.hasFTS5 {
            Logger.warning("SQLite FTS5 extension is not available on this system.")
            Logger.warning("File search will work but will use slower LIKE-based queries.")
            Logger.warning("Install a SQLite build with SQLITE_ENABLE_FTS5 for full-text search.")
        }

        self.indexController.indexFiles()
        self.indexController.configure(reindexInterval: resolvedReindexInterval())

        let port = resolvedServerPort()

        self.serverController = ServerController(port: port, spec: self.spec)

        // SECURITY (A_009): init persistent identity key for TOFU
        let strictIdentity = (self.config["security", "strict_identity"] as? Bool)
            ?? {
                if let s = (self.config["security", "strict_identity"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    return ["1", "true", "yes", "on"].contains(s)
                }
                return true
            }()
        if let identity = ServerIdentity(workingDirectory: self.workingDirectoryPath,
                                         strictIdentity: strictIdentity) {
            self.serverController.serverIdentity = identity
            Logger.info("Server identity fingerprint: \(identity.formattedFingerprint())")
        } else {
            Logger.warning("Could not load server identity key — TOFU will be disabled for this session")
        }

        self.serverController.listen()
    }

    public func stop() {
        self.serverController?.stop()
        self.indexController?.configure(reindexInterval: 0)
    }

    private func resolvedServerPort() -> Int {
        if let value = self.config["server", "port"] as? Int, (1...65535).contains(value) {
            return value
        }

        if let raw = self.config["server", "port"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = Int(trimmed), (1...65535).contains(parsed) {
                return parsed
            }
            Logger.warning("Invalid server.port value '\(raw)'. Falling back to default port \(DEFAULT_PORT).")
            return DEFAULT_PORT
        }

        return DEFAULT_PORT
    }

    public func reloadConfig() {
        Logger.info("Reloading configuration from \(self.configPath)...")
        guard self.config.load() else {
            Logger.error("Failed to reload config from \(self.configPath)")
            return
        }

        reloadLogLevel()

        if let raw = self.config["server", "files"] as? String {
            let newPath = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newPath.isEmpty && newPath != self.rootPath {
                Logger.info("  server.files: \(self.rootPath) → \(newPath)")
                self.rootPath = newPath
                self.filesController.rootPath = newPath
            }
        }

        // Re-arm the periodic reindex timer if the interval changed.
        self.indexController.configure(reindexInterval: resolvedReindexInterval())

        self.serverController.reloadConfig()
    }

    /// Apply `[log] level` from config, unless `--debug` is active (debug mode pins to DEBUG).
    private func reloadLogLevel() {
        guard !debugMode else { return }
        guard let raw = self.config["log", "level"] as? String else { return }
        guard let level = Logger.LogLevel.fromString(raw) else {
            Logger.warning("  log.level: unknown value '\(raw)' — keeping current level")
            return
        }
        let current = Logger.currentLevel
        if level != current {
            Logger.info("  log.level: \(current.description.lowercased()) → \(level.description.lowercased())")
            Logger.setMaxLevel(level)
        }
    }

    /// Read the reindex interval from config.
    /// Reads `[settings] reindex_interval` (the key written by WiredServerApp)
    /// with a fallback to `[index] interval` for backward compatibility.
    /// Returns the default (3600 s) if neither key is present or parseable.
    /// Minimum enforced value: 60 seconds; 0 means disabled.
    private func resolvedReindexInterval() -> TimeInterval {
        let defaultInterval: TimeInterval = 3600

        // Primary key — written by WiredServerApp FilesTabView.
        let primaryKeys: [(String, String)] = [("settings", "reindex_interval"), ("index", "interval")]

        for (section, key) in primaryKeys {
            if let value = self.config[section, key] as? Int {
                return value == 0 ? 0 : max(60, TimeInterval(value))
            }
            if let raw = self.config[section, key] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if let parsed = Int(trimmed) {
                    return parsed == 0 ? 0 : max(60, TimeInterval(parsed))
                }
                Logger.warning("Invalid \(section).\(key) value '\(raw)'. Trying next key.")
            }
        }
        return defaultInterval
    }

    private func bootstrapDefaultContentIfNeeded() {
        bootstrapWelcomeBoardIfNeeded()
        bootstrapDefaultFilesIfNeeded()
    }

    private func bootstrapWelcomeBoardIfNeeded() {
        guard !self.bootstrapStateStore.isCompleted(welcomeBoardSeed) else { return }

        defer {
            self.bootstrapStateStore.markCompleted(welcomeBoardSeed)
        }

        guard self.boardsController.boards.isEmpty,
              self.boardsController.threads.isEmpty,
              self.boardsController.posts.isEmpty else {
            return
        }

        guard self.boardsController.addBoard(
            path: defaultWelcomeBoardPath,
            owner: "admin",
            group: "admin",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: true
        ) != nil else {
            return
        }

        _ = self.boardsController.addThread(
            board: defaultWelcomeBoardPath,
            subject: defaultWelcomeThreadSubject,
            text: defaultWelcomeThreadBody,
            nick: "Wired Server",
            login: "admin",
            icon: nil
        )
    }

    private func bootstrapDefaultFilesIfNeeded() {
        guard !self.bootstrapStateStore.isCompleted(defaultFilesSeed) else { return }

        defer {
            self.bootstrapStateStore.markCompleted(defaultFilesSeed)
        }

        guard isDirectoryEmpty(atPath: self.rootPath) else {
            return
        }

        let upload = self.rootPath.stringByAppendingPathComponent(path: "Upload")
        let dropbox = self.rootPath.stringByAppendingPathComponent(path: "DropBox")
        let dropboxPrivileges = FilePrivilege(owner: "admin", group: "", mode: [.ownerRead, .ownerWrite, .everyoneWrite])

        self.filesController.createDefaultDirectoryIfMissing(path: upload, type: .uploads, privileges: nil)
        self.filesController.createDefaultDirectoryIfMissing(path: dropbox, type: .dropbox, privileges: dropboxPrivileges)
    }

    private func isDirectoryEmpty(atPath path: String) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return false
        }

        return entries.isEmpty
    }

}
