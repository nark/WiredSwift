//
//  main.swift
//  Server
//
//  Created by Rafael Warnault on 19/03/2021.
//

import Foundation
import ArgumentParser
import WiredSwift

public var App:AppController!

struct Wired: ParsableCommand {
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

    @Argument(help: "Optional working directory path. For compatibility, an .xml path here is treated as the specification file path.")
    var path: String?
    
    mutating func run() throws {
        let resolved = try resolvePaths()

        ensureDefaultConfigExists(at: resolved.configPath)
        bootstrapRuntimeFiles(using: resolved)
        configureLogger(logFilePath: resolved.logPath)

        App = AppController(
            specPath: resolved.specPath,
            dbPath: resolved.dbPath,
            rootPath: resolved.filesRootPath,
            configPath: resolved.configPath,
            workingDirectoryPath: resolved.workingDirectoryPath
        )
        
        App.start()
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
            shouldBootstrapSpec: (spec == nil && inferredSpec == nil)
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

[advanced]
compression = ALL
cipher = SECURE_ONLY
checksum = SECURE_ONLY
"""

        do {
            try defaultConfig.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            Logger.info("Created default config at \(path)")
        } catch {
            Logger.error("Cannot create default config at \(path): \(error.localizedDescription)")
        }
    }

    private func configureLogger(logFilePath: String) {
        Logger.setDestinations([.Stdout, .File], filePath: "wired.log")
        _ = Logger.setFileDestination(logFilePath)
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
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        return [
            sourceDir
                .appendingPathComponent("wired.xml").path,
            sourceDir
                .deletingLastPathComponent()
                .appendingPathComponent("WiredSwift")
                .appendingPathComponent("wired.xml").path,
            executableDir.stringByAppendingPathComponent(path: "wired.xml"),
            executableDir
                .stringByAppendingPathComponent(path: "../share/wired3/wired.xml")
        ].map { standardizedAbsolutePath($0, base: nil) }
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
}

// ignore writing to closed socket
signal(SIGPIPE, SIG_IGN)

Wired.main()
