// WiredChatBot — BotLogger.swift
// Thin wrapper around WiredSwift.Logger.
//
// Logger API notes (from source):
//   - setDestinations([.File], filePath: name) sets shared.fileName = name
//   - setFileDestination(directory) appends shared.fileName to directory if not already present
//   - setMaxLevel: rawValue check is 0..5, so .VERBOSE (6) is never applied → use .DEBUG instead

import Foundation
import WiredSwift

public enum BotLogger {

    public static func configure(level: String, filePath: String?) {
        // VERBOSE maps to DEBUG because Logger.setMaxLevel guards rawValue <= 5
        switch level.uppercased() {
        case "VERBOSE", "DEBUG": Logger.setMaxLevel(.DEBUG)
        case "INFO":             Logger.setMaxLevel(.INFO)
        case "WARNING":          Logger.setMaxLevel(.WARNING)
        case "ERROR":            Logger.setMaxLevel(.ERROR)
        default:                 Logger.setMaxLevel(.INFO)
        }

        if let fullPath = filePath {
            // Split into directory + filename so Logger constructs the correct path
            let url      = URL(fileURLWithPath: fullPath)
            let fileName = url.lastPathComponent
            let dir      = url.deletingLastPathComponent().path

            // setDestinations(filePath:) sets shared.fileName = fileName
            Logger.setDestinations([.File], filePath: fileName)
            // setFileDestination appends fileName to dir → dir/fileName
            _ = Logger.setFileDestination(dir)
        } else {
            Logger.setDestinations([.Stdout])
        }
    }

    public static func info   (_ msg: String) { Logger.info   ("[Bot] \(msg)") }
    public static func debug  (_ msg: String) { Logger.debug  ("[Bot] \(msg)") }
    public static func warning(_ msg: String) { Logger.warning("[Bot] \(msg)") }
    public static func error  (_ msg: String) { Logger.error  ("[Bot] \(msg)") }
    public static func fatal  (_ msg: String) { Logger.fatal  ("[Bot] \(msg)") }
}
