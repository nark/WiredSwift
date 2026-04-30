//
//  main.swift
//  Server
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import ArgumentParser
import WiredSwift
import wired3Lib
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct Wired: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Wired 3 server"
    )

    @Flag(name: [.customLong("version")], help: "Print version and exit")
    var showVersion = false

    @Flag(name: [.customLong("reload"), .customShort("r")], help: "Send reload signal to running wired3 instance")
    var reload = false

    @Flag(name: [.customLong("index"), .customShort("i")], help: "Trigger a full file index (cancels any rebuild in progress) on a running wired3 instance")
    var index = false

    @Flag(help: "Enable debug mode")
    var debugMode = false

    @Option(name: [.customLong("working-directory"), .customShort("w")], help: "Working directory containing server runtime files")
    var workingDirectory: String?

    @Option(help: "Sqlite database file")
    var db: String?

    @Option(help: "Server root files path")
    var root: String?

    @Option(help: "Server config file path (.ini)")
    var config: String?

    @Option(help: "Path to XML specification file")
    var spec: String?

    @Option(name: .customLong("migrate-from"),
            help: "Path to a Wired 2.5 SQLite database. Migrates users, groups and bans into the Wired 3 database, then exits.")
    var migrateFrom: String?

    @Flag(name: .customLong("overwrite"),
          help: "When used with --migrate-from: overwrite existing records in the Wired 3 database.")
    var overwrite = false

    @Option(name: .customLong("check-access"),
            help: "Test whether this binary can read the given path, then exit (0 = ok, 1 = denied). Used by WiredServerApp for FDA status checks.")
    var checkAccess: String?

    @Argument(help: "Optional working directory path. For compatibility, an .xml path here is treated as the specification file path.")
    var path: String?

    mutating func run() throws {
        if let accessPath = checkAccess {
            let url = URL(fileURLWithPath: (accessPath as NSString).expandingTildeInPath)
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
                Foundation.exit(0)
            } catch {
                Foundation.exit(1)
            }
        }

        if showVersion {
            print(WiredServerVersion.display)
            return
        }

        let resolved = try resolvePaths()

        if reload {
            handleReload(pidPath: resolved.pidPath)
            return
        }

        if index {
            handleIndex(pidPath: resolved.pidPath)
            return
        }

        ensureDefaultConfigExists(at: resolved.configPath)
        if ConfigFileDefaults.ensureStrictIdentitySetting(at: resolved.configPath) {
            Logger.info("Backfilled security.strict_identity in \(resolved.configPath)")
        }
        bootstrapRuntimeFiles(using: resolved)
        configureLogger(logFilePath: resolved.logPath, configPath: resolved.configPath)

        // ── Wired 2.5 → Wired 3 migration ────────────────────────────────────────
        if let rawSourcePath = migrateFrom {
            // Disable C-stdio buffering so every print() call writes immediately.
            // Without this, output is fully-buffered on pipes/files and gets lost on crash.
            setvbuf(stdout, nil, _IONBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
            let expandedSourcePath = (rawSourcePath as NSString).expandingTildeInPath
            guard let spec = P7Spec(withUrl: URL(fileURLWithPath: resolved.specPath)) else {
                fputs("wired3: cannot load spec at \(resolved.specPath)\n", stderr)
                Foundation.exit(1)
            }
            let dbController = DatabaseController(
                baseURL: URL(fileURLWithPath: resolved.dbPath),
                spec: spec
            )
            guard dbController.initDatabase() else {
                fputs("wired3: cannot open database at \(resolved.dbPath)\n", stderr)
                Foundation.exit(1)
            }
            let migrator = MigrationController(
                sourcePath: expandedSourcePath,
                dbQueue: dbController.dbQueue,
                overwrite: overwrite
            )
            do {
                let result = try migrator.run()
                result.printSummary()
            } catch {
                fputs("wired3: migration failed: \(error)\n", stderr)
                Foundation.exit(1)
            }
            return
        }

        Logger.info("Starting \(WiredServerVersion.display)")

        App = AppController(
            specPath: resolved.specPath,
            dbPath: resolved.dbPath,
            rootPath: resolved.filesRootPath,
            configPath: resolved.configPath,
            workingDirectoryPath: resolved.workingDirectoryPath,
            debugMode: debugMode
        )

        writePID(to: resolved.pidPath)

        // Install SIGHUP handler for live config reload.
        signal(SIGHUP, SIG_IGN)
        let sighupSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: DispatchQueue.global())
        sighupSource.setEventHandler {
            Logger.info("SIGHUP received, reloading configuration...")
            App.reloadConfig()
        }
        sighupSource.resume()

        // Install SIGUSR1 handler for on-demand file reindex.
        // forceReindex() cancels any running traversal and starts a fresh one.
        signal(SIGUSR1, SIG_IGN)
        let sigusr1Source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: DispatchQueue.global())
        sigusr1Source.setEventHandler {
            Logger.info("SIGUSR1 received, triggering full file reindex...")
            App.indexController.forceReindex()
        }
        sigusr1Source.resume()

        App.start()

        sighupSource.cancel()
        sigusr1Source.cancel()
        try? FileManager.default.removeItem(atPath: resolved.pidPath)
    }

    private func writePID(to path: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            try "\(pid)\n".write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            Logger.warning("Could not write PID file at \(path): \(error.localizedDescription)")
        }
    }

    private func handleIndex(pidPath: String) {
        let candidates = pidFileCandidates(primary: pidPath)
        guard let foundPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            fputs("wired3: cannot find PID file. Tried:\n", stderr)
            candidates.forEach { fputs("  \($0)\n", stderr) }
            fputs("Is wired3 running? You can also use: wired3 -i -w <working-directory>\n", stderr)
            Foundation.exit(1)
        }
        guard let pidString = try? String(contentsOfFile: foundPath, encoding: .utf8) else {
            fputs("wired3: cannot read PID file at \(foundPath)\n", stderr)
            Foundation.exit(1)
        }
        let trimmed = pidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed) else {
            fputs("wired3: invalid PID '\(trimmed)' in \(foundPath)\n", stderr)
            Foundation.exit(1)
        }
        guard kill(pid, SIGUSR1) == 0 else {
            let errStr = String(cString: strerror(errno))
            fputs("wired3: failed to send index signal to process \(pid): \(errStr)\n", stderr)
            Foundation.exit(1)
        }
        print("wired3: index signal sent to process \(pid)")
    }

    private func handleReload(pidPath: String) {
        let candidates = pidFileCandidates(primary: pidPath)
        guard let foundPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            fputs("wired3: cannot find PID file. Tried:\n", stderr)
            candidates.forEach { fputs("  \($0)\n", stderr) }
            fputs("Is wired3 running? You can also use: wired3 -r -w <working-directory>\n", stderr)
            Foundation.exit(1)
        }
        guard let pidString = try? String(contentsOfFile: foundPath, encoding: .utf8) else {
            fputs("wired3: cannot read PID file at \(foundPath)\n", stderr)
            Foundation.exit(1)
        }
        let trimmed = pidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed) else {
            fputs("wired3: invalid PID '\(trimmed)' in \(foundPath)\n", stderr)
            Foundation.exit(1)
        }
        guard kill(pid, SIGHUP) == 0 else {
            let errStr = String(cString: strerror(errno))
            fputs("wired3: failed to send reload signal to process \(pid): \(errStr)\n", stderr)
            Foundation.exit(1)
        }
        print("wired3: reload signal sent to process \(pid)")
    }

    private func pidFileCandidates(primary: String) -> [String] {
        var candidates = [primary]
        if let execPath = CommandLine.arguments.first {
            let execDir = URL(fileURLWithPath: execPath).resolvingSymlinksInPath()
                .deletingLastPathComponent()
            // bin/wired3 layout → working dir is one level up
            candidates.append(execDir.deletingLastPathComponent()
                .appendingPathComponent("wired3.pid").path)
            // wired3 directly in working dir
            candidates.append(execDir.appendingPathComponent("wired3.pid").path)
        }
        return candidates
    }

    private func resolvePaths() throws -> ResolvedPaths {
        let fileManager = FileManager.default
        let currentDirectory = standardizedAbsolutePath(fileManager.currentDirectoryPath, base: nil)

        var inferredWorkingDirectory: String?
        var inferredSpec: String?

        if let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty {
            let candidate = standardizedAbsolutePath(rawPath, base: currentDirectory)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory)

            if (exists && isDirectory.boolValue) || rawPath.hasSuffix("/") {
                inferredWorkingDirectory = candidate
            } else if candidate.lowercased().hasSuffix(".xml") {
                inferredSpec = candidate
            } else {
                inferredWorkingDirectory = candidate
            }
        }

        let resolvedWorkingDirectory = standardizedAbsolutePath(
            workingDirectory ?? inferredWorkingDirectory ?? currentDirectory,
            base: currentDirectory
        )

        if !fileManager.fileExists(atPath: resolvedWorkingDirectory) {
            try fileManager.createDirectory(atPath: resolvedWorkingDirectory, withIntermediateDirectories: true)
        }

        let configDefault = resolvedWorkingDirectory.stringByAppendingPathComponent(path: "etc/config.ini")
        let legacyConfigDefault = resolvedWorkingDirectory.stringByAppendingPathComponent(path: "config.ini")
        let resolvedConfig: String
        if let config {
            resolvedConfig = standardizedAbsolutePath(config, base: resolvedWorkingDirectory)
        } else if fileManager.fileExists(atPath: configDefault) || !fileManager.fileExists(atPath: legacyConfigDefault) {
            resolvedConfig = standardizedAbsolutePath(configDefault, base: resolvedWorkingDirectory)
        } else {
            resolvedConfig = standardizedAbsolutePath(legacyConfigDefault, base: resolvedWorkingDirectory)
        }

        let configuredFilesPath = configuredFilesRoot(fromConfigAt: resolvedConfig)
        let resolvedDB = standardizedAbsolutePath(
            db ?? resolvedWorkingDirectory.stringByAppendingPathComponent(path: "wired3.db"),
            base: resolvedWorkingDirectory
        )

        let resolvedFilesRoot = standardizedAbsolutePath(
            root ?? configuredFilesPath ?? resolvedWorkingDirectory.stringByAppendingPathComponent(path: "files"),
            base: resolvedWorkingDirectory
        )

        let resolvedSpec = standardizedAbsolutePath(
            spec ?? inferredSpec ?? resolvedWorkingDirectory.stringByAppendingPathComponent(path: "wired.xml"),
            base: resolvedWorkingDirectory
        )

        let resolvedLogPath = standardizedAbsolutePath(
            resolvedWorkingDirectory.stringByAppendingPathComponent(path: "wired.log"),
            base: nil
        )

        return ResolvedPaths(
            workingDirectoryPath: resolvedWorkingDirectory,
            configPath: resolvedConfig,
            dbPath: resolvedDB,
            filesRootPath: resolvedFilesRoot,
            specPath: resolvedSpec,
            logPath: resolvedLogPath,
            shouldBootstrapSpec: (spec == nil && inferredSpec == nil),
            pidPath: resolvedWorkingDirectory.stringByAppendingPathComponent(path: "wired3.pid")
        )
    }

    private func standardizedAbsolutePath(_ path: String, base: String?) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        let parent = base ?? FileManager.default.currentDirectoryPath
        let parentURL = URL(fileURLWithPath: parent, isDirectory: true)
        return URL(fileURLWithPath: expanded, relativeTo: parentURL).standardizedFileURL.path
    }

    private func ensureDefaultConfigExists(at path: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }

        let parentDirectory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDirectory, withIntermediateDirectories: true)

        let defaultConfig = """
[transfers]
downloads = 10
downloadSpeed = 0
uploadSpeed = 0
uploads = 10

[server]
banner = banner.png
files = files
name = Wired Server
description = Welcome to Wired Server
port = 4871

[settings]
trackers = ["wired.read-write.fr"]
reindex_interval = 3600

[database]
snapshot_interval = 86400
event_retention = never

[advanced]
compression = ALL
cipher = SECURE_ONLY
checksum = SECURE_ONLY

[security]
strict_identity = yes

[log]
# Log level: fatal | error | warning | notice | info | debug | verbose
# Use --debug at startup to force debug level regardless of this setting.
level = info
"""

        do {
            try defaultConfig.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            Logger.info("Created default config at \(path)")
        } catch {
            Logger.error("Cannot create default config at \(path): \(error.localizedDescription)")
        }
    }

    private func configureLogger(logFilePath: String, configPath: String) {
        Logger.setDestinations([.Stdout, .File], filePath: "wired.log")
        _ = Logger.setFileDestination(logFilePath)
        // Rotate at most once per day (not every minute, which is the default).
        Logger.setTimeLimit(.Day)
        // Allow up to 50 MB before size-based rotation.
        Logger.setLimitLogSize(50 * 1024 * 1024)

        // --debug flag forces DEBUG level and overrides config.
        if debugMode {
            Logger.setMaxLevel(.DEBUG)
            return
        }

        // Read [log] level from config.ini (default: info).
        let level = resolvedLogLevel(fromConfigAt: configPath)
        Logger.setMaxLevel(level)
    }

    /// Read `[log] level` from config.ini, fallback to `.INFO`.
    private func resolvedLogLevel(fromConfigAt configPath: String) -> Logger.LogLevel {
        guard FileManager.default.fileExists(atPath: configPath) else { return .INFO }
        let cfg = Config(withPath: configPath)
        guard cfg.load() else { return .INFO }
        if let raw = cfg["log", "level"] as? String,
           let level = Logger.LogLevel.fromString(raw) {
            return level
        }
        return .INFO
    }

    private func configuredFilesRoot(fromConfigAt configPath: String) -> String? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let cfg = Config(withPath: configPath)
        guard cfg.load() else {
            return nil
        }

        guard let filesPath = cfg["server", "files"] as? String else {
            return nil
        }

        let trimmed = filesPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func configuredBannerPath(fromConfigAt configPath: String) -> String? {
        guard FileManager.default.fileExists(atPath: configPath) else {
            return nil
        }

        let cfg = Config(withPath: configPath)
        guard cfg.load() else {
            return nil
        }

        guard let bannerPath = cfg["server", "banner"] as? String else {
            return nil
        }

        let trimmed = bannerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func bootstrapRuntimeFiles(using resolved: ResolvedPaths) {
        let fileManager = FileManager.default

        try? fileManager.createDirectory(atPath: resolved.workingDirectoryPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: resolved.filesRootPath, withIntermediateDirectories: true)

        touchFileIfMissing(at: resolved.logPath)

        if resolved.shouldBootstrapSpec,
           !fileManager.fileExists(atPath: resolved.specPath) {
            if !copyDefaultSpec(to: resolved.specPath) {
                Logger.warning("Could not bootstrap wired.xml at \(resolved.specPath). Use --spec to provide a custom path.")
            }
        }

        let configuredBanner = configuredBannerPath(fromConfigAt: resolved.configPath)
        let bannerPath = standardizedAbsolutePath(
            configuredBanner ?? resolved.workingDirectoryPath.stringByAppendingPathComponent(path: "banner.png"),
            base: resolved.workingDirectoryPath
        )
        if !fileManager.fileExists(atPath: bannerPath) {
            createDefaultBanner(at: bannerPath)
        }
    }

    private func touchFileIfMissing(at path: String) {
        guard !FileManager.default.fileExists(atPath: path) else { return }
        let parentDirectory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: path, contents: Data(), attributes: nil)
    }

    private func copyDefaultSpec(to destinationPath: String) -> Bool {
        let fileManager = FileManager.default
        let destinationDirectory = (destinationPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)

        let sourceCandidates = defaultSpecSourceCandidates()
        for sourcePath in sourceCandidates where fileManager.fileExists(atPath: sourcePath) {
            do {
                if fileManager.fileExists(atPath: destinationPath) {
                    try fileManager.removeItem(atPath: destinationPath)
                }
                try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
                Logger.info("Bootstrapped wired.xml at \(destinationPath)")
                return true
            } catch {
                continue
            }
        }

        return false
    }

    private func defaultSpecSourceCandidates() -> [String] {
        let fileManager = FileManager.default
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? fileManager.currentDirectoryPath)
            .resolvingSymlinksInPath()
        let executableDir = executableURL.deletingLastPathComponent().path
        var candidates = WiredProtocolSpec.bundledSpecURL().map { [$0.path] } ?? []
        candidates += [
            executableDir.stringByAppendingPathComponent(path: "wired.xml"),
            executableDir
                .stringByAppendingPathComponent(path: "../share/wired3/wired.xml")
        ]

        return candidates.map { standardizedAbsolutePath($0, base: nil) }
    }

    private func createDefaultBanner(at path: String) {
        let fileManager = FileManager.default
        let parentDirectory = (path as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: parentDirectory, withIntermediateDirectories: true)

        for sourcePath in defaultBannerSourceCandidates() where fileManager.fileExists(atPath: sourcePath) {
            do {
                if fileManager.fileExists(atPath: path) {
                    try fileManager.removeItem(atPath: path)
                }
                try fileManager.copyItem(atPath: sourcePath, toPath: path)
                Logger.info("Bootstrapped banner at \(path)")
                return
            } catch {
                continue
            }
        }

        Logger.warning("Could not bootstrap banner at \(path): no source banner found")
    }

    private func defaultBannerSourceCandidates() -> [String] {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? fileManager.currentDirectoryPath)
            .resolvingSymlinksInPath()
        let executableDir = executableURL.deletingLastPathComponent().path
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        return [
            currentDir
                .stringByAppendingPathComponent(path: "Sources/wired3/banner.png"),
            sourceDir
                .appendingPathComponent("banner.png").path,
            executableDir.stringByAppendingPathComponent(path: "banner.png"),
            executableDir
                .stringByAppendingPathComponent(path: "../share/wired3/banner.png")
        ].map { standardizedAbsolutePath($0, base: nil) }
    }
}

private struct ResolvedPaths {
    let workingDirectoryPath: String
    let configPath: String
    let dbPath: String
    let filesRootPath: String
    let specPath: String
    let logPath: String
    let shouldBootstrapSpec: Bool
    let pidPath: String
}

// ignore writing to closed socket
signal(SIGPIPE, SIG_IGN)

Wired.main()
