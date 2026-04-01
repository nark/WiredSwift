// WiredChatBot — ConfigLoader.swift
// Loads, validates and saves JSON configuration files.

import Foundation
import WiredSwift

public enum ConfigError: Error, LocalizedError {
    case fileNotFound(String)
    case parseError(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "Config file not found at: \(p)"
        case .parseError(let msg): return "Config parse error: \(msg)"
        }
    }
}

public class ConfigLoader {

    // MARK: - Load

    public static func load(from path: String) throws -> BotConfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ConfigError.fileNotFound(path)
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        do {
            return try JSONDecoder().decode(BotConfig.self, from: data)
        } catch {
            throw ConfigError.parseError(error.localizedDescription)
        }
    }

    // MARK: - Save

    public static func save(_ config: BotConfig, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public static func generateDefault(at path: String) throws {
        try save(BotConfig(), to: path)
    }

    // MARK: - Spec path discovery

    /// Searches well-known locations for wired.xml.
    /// `hint` is checked first (from config or CLI flag).
    public static func findSpecPath(hint: String? = nil) -> String? {
        var candidates: [String] = []

        if let hint = hint { candidates.append(hint) }

        if let bundledPath = WiredProtocolSpec.bundledSpecURL()?.path {
            candidates.append(bundledPath)
        }

        // Relative to executable
        if let execPath = Bundle.main.executablePath {
            let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent()
            candidates += [
                execDir.appendingPathComponent("wired.xml").path,
                execDir.appendingPathComponent("Resources/wired.xml").path,
                execDir.appendingPathComponent("../Resources/wired.xml").path
            ]
        }

        // Standard paths
        candidates += [
            "./wired.xml",
            "./Resources/wired.xml",
            "/etc/wiredbot/wired.xml",
            "/usr/share/wiredbot/wired.xml",
            "/usr/local/share/wiredbot/wired.xml"
        ]

        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
