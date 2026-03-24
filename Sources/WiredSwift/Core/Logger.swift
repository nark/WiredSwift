//
//  Logger.swift
//  Wired
//
//  Created by Paul Repain on 15/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif

public protocol LoggerDelegate: class {
    /// Called with the fully-formatted output string (for legacy consumers).
    func loggerDidOutput(logger: Logger, output: String)

    /// Called with structured log data — implement this to capture entries for
    /// real-time broadcast (e.g. `wired.log.message`) to subscribed clients.
    func loggerDidLog(level: Logger.LogLevel, message: String, date: Date)
}

public extension LoggerDelegate {
    func loggerDidOutput(logger: Logger, output: String) {}
    func loggerDidLog(level: Logger.LogLevel, message: String, date: Date) {}
}

/**
 This class is for printing log, either in the console or in a file.
 Log can have different type of severity, and different type of output as
 stated before.

 */
public class Logger {


    /**
     Enumeration for severity level
     */
    public enum LogLevel : Int {
        case FATAL   = 0
        case ERROR   = 1
        case WARNING = 2
        case INFO    = 3
        case NOTICE  = 4
        case DEBUG   = 5
        case VERBOSE = 6

        public var description: String {
            switch self {
            case .FATAL:   return "FATAL"
            case .ERROR:   return "ERROR"
            case .WARNING: return "WARNING"
            case .NOTICE:  return "NOTICE"
            case .INFO:    return "INFO"
            case .DEBUG:   return "DEBUG"
            case .VERBOSE: return "VERBOSE"
            }
        }

        /// Parse a human-readable level name from config (case-insensitive).
        /// Accepted: fatal, error, warning/warn, notice, info, debug, verbose
        public static func fromString(_ string: String) -> LogLevel? {
            switch string.trimmingCharacters(in: .whitespaces).lowercased() {
            case "fatal":           return .FATAL
            case "error":           return .ERROR
            case "warning", "warn": return .WARNING
            case "notice":          return .NOTICE
            case "info":            return .INFO
            case "debug":           return .DEBUG
            case "verbose":         return .VERBOSE
            default:                return nil
            }
        }
    }

    /**
     Enumeration for type of output
     - Stdout: console
     - File: file
     */
    public enum Output {
        case Stdout
        case File
    }

    public enum TimeLimit: Int {
        case Minute = 0
        case Hour   = 1
        case Day    = 2
        case Month  = 3
    }



    /**/

    public var targetName:String {
        get {
            if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
                return bundleName
            }
            return "Wired3"
        }
    }
    
    private static var shared = Logger()
    public static var delegate:LoggerDelegate? = nil
    private let fileLock = NSRecursiveLock()
    
    private func withFileLock<T>(_ body: () -> T) -> T {
        fileLock.lock()
        defer { fileLock.unlock() }
        return body()
    }
    
    private var maxLevel: Int       = 6
    public lazy var fileName:String = targetName + ".log"
    lazy var filePath:URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    public var outputs:[Output]     = [.Stdout]
    public var sizeLimit:UInt64     = 1_000_000
    public var timeLimit:TimeLimit  = .Minute
    public var startDate:Date       = Date()
    
    
    /**/


    public static func notice(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.NOTICE.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.NOTICE)
        }
    }

    public static func info(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.INFO.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.INFO)
        }
    }

    public static func verbose(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.NOTICE.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.NOTICE)
        }
    }

    public static func debug(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.DEBUG.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.DEBUG)
        }
    }

    public static func warning(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.WARNING.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.WARNING)
        }
    }

    public static func error(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.ERROR.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.ERROR)
        }
    }
    
    public static func error(_ error:WiredError, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.ERROR.rawValue <= shared.maxLevel {
            shared.output(string: error.message, error.title, file, function, line: line, severity: LogLevel.ERROR)
        }
    }

    public static func fatal(_ string:String, _ tag:String? = nil, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        if LogLevel.FATAL.rawValue <= shared.maxLevel {
            shared.output(string: string, tag, file, function, line: line, severity: LogLevel.FATAL)
        }
    }
    


    /**
     Format the output
     Adds a newline for writting in file
     - parameter string: the message to be sent
     - parameter tag: the tag to be printed; name of the target by default
     - parameter file: file where the log was called
     - parameter function: same
     - parameter line: same
     - parameter severity: level of severity of the log (see enum)

     */
    public func output(string:String, _ tag:String?, _ file: String = #file, _ function: String = #function, line: Int = #line, severity:LogLevel) {
        let date = Date()
        let df = DateFormatter()
        // formatting date
        df.dateFormat = "dd-MM-yyyy HH:mm:ss"
        // if tag is nil, tag is name of target
        let tagName:String = tag ?? self.targetName

        /* DATE SEVERITY -> [TAG]        MESSAGE */
        let outputString:String = "\(df.string(from: date)) \(severity.description) -> [\(tagName)]\t \(string)"
        
        if let d = Logger.delegate {
            d.loggerDidOutput(logger: self, output: outputString)
            d.loggerDidLog(level: severity, message: string, date: date)
        }

        let currentOutputs = withFileLock { outputs }
        // managing different type of output (console or file)
        for output in currentOutputs {
            switch output {
            case .Stdout:
                consoleLog(message: outputString)
            case .File:
                if fileLog(message: outputString + "\n") {}
            }

        }
    }

    /**
     Prints to the console
     - parameter message: the log to be printed in the console

     */
    public func consoleLog(message:String) {
        print(message)
        fflush(stdout)
    }

    /**
     Write in file. Creates a file if the file doesn't exist. Append at
     the end of the file.
     - parameter message: the log to be written in the file
     - returns: true if filepath is correct

     */
    public func fileLog(message: String) -> Bool {
        fileLock.lock()
        defer { fileLock.unlock() }

        guard let fileURL = filePath else {
            return false
        }

        let path = fileURL.path

        if getFileSize(atPath: path) > self.sizeLimit {
            do {
                try FileManager.default.removeItem(at: fileURL)
            }
            catch {}
        }

        Logger.eraseFileByTime()

        // Ensure the parent directory exists before opening the log file.
        if let directoryPath = fileURL.deletingLastPathComponent().path as String? {
            do {
                try FileManager.default.createDirectory(
                    atPath: directoryPath,
                    withIntermediateDirectories: true
                )
            } catch {
                return false
            }
        }

        return appendLinePOSIX(path: path, message: message)
    }


    /**
     Set the destination for output : file (with name of file), console.
     Default log file is dicom.log
     - parameter destinations: all the destinations where the logs are outputted
     - parameter filePath: path of the logfile

     */
    public static func setDestinations(_ destinations: [Output], filePath: String? = nil) {
        shared.withFileLock {
            shared.outputs = destinations
            if let fileName:String = filePath {
                shared.fileName = fileName
            }
        }
    }

    /**
     Set the file path where the logs are printed
     By default, the path is ~/Documents/\(targetName).log
     - parameter withPath: path of the file, the filename is appended at the end
     if there is none
     - returns: false is path is nil

     */
    public static func setFileDestination(_ withPath: String?) -> Bool {
        guard var path = withPath else {
            return false
        }

        shared.withFileLock {
            if !path.contains(self.shared.fileName) {
                path += "/" + self.shared.fileName
            }
            shared.filePath = URL(fileURLWithPath: path)
        }

        return true
    }


    /**
     Set the level of logs printed
     - parameter at: the log level to be set

     */
    public static func setMaxLevel(_ at: LogLevel) {
        shared.maxLevel = at.rawValue
    }

    /// The currently active log level.
    public static var currentLevel: LogLevel {
        return LogLevel(rawValue: shared.maxLevel) ?? .INFO
    }

    public static func setLimitLogSize(_ at: UInt64) {
        shared.withFileLock {
            shared.sizeLimit = at
        }
    }

    public static func addDestination(_ dest: Output) {
        shared.withFileLock {
            shared.outputs.append(dest)
        }
    }

    public static func removeDestination(_ dest: Output) {
        shared.withFileLock {
            shared.outputs = shared.outputs.filter{$0 != dest}
        }
    }

    public static func setTimeLimit(_ at: TimeLimit) {
        let startDate = Date()
        shared.withFileLock {
            shared.timeLimit = at
            shared.startDate = startDate /* the date is reset */
        }
        UserDefaults.standard.set(startDate, forKey: "startDate")
    }

    /**
     Erase the log file

     */
    public static func eraseFileByTime() {
        let startDate = shared.withFileLock { shared.startDate }
        let range = -Int(startDate.timeIntervalSinceNow)
        let t:Int

        let timeLimit = shared.withFileLock { shared.timeLimit }
        switch timeLimit {
        case .Minute:
            t = range / 60
        case .Hour:
            t = range / 3600
        case .Day:
            t = range / 86400
        case .Month:
            t = range / 100000
        }

        if t >= 1 {
            if let path = shared.withFileLock({ shared.filePath }) {
                Logger.removeLogFile(path)
                shared.withFileLock {
                    shared.startDate = Date()
                }
            }
        }
    }

    /**
     Delete the log file
     - parameter at: the URL where the log file is

     */
    public static func removeLogFile(_ at: URL) {
        do {
            try FileManager.default.removeItem(at: at)
        }
        catch {}
    }



    /**/


    private func getFileSize(atPath path: String) -> UInt64 {
        var fileStat = stat()
        let result = path.withCString { cString in
            stat(cString, &fileStat)
        }
        guard result == 0 else {
            return 0
        }
        return UInt64(fileStat.st_size)
    }

    private func appendLinePOSIX(path: String, message: String) -> Bool {
        let fd = path.withCString { cPath in
            open(cPath, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        }
        guard fd >= 0 else {
            return false
        }
        defer { close(fd) }

        let bytes = Array(message.utf8)
        let wrote = bytes.withUnsafeBytes { rawBuffer -> Int in
            guard let base = rawBuffer.baseAddress else {
                return 0
            }
            return write(fd, base, rawBuffer.count)
        }
        return wrote == bytes.count
    }

    public static func getSizeLimit() -> UInt64 {
        shared.withFileLock { shared.sizeLimit }
    }


    public static func getFileDestination() -> String? {
        shared.withFileLock { shared.filePath?.path }
    }

    public static func getTimeLimit() -> Int {
        shared.withFileLock { shared.timeLimit.rawValue }
    }







    /**
     Set the logger according to the settings in UserDefaults

     */
    public static func setPreferences() {
        /* set the destinations output */
        var destinations:[Logger.Output] = []
        if UserDefaults.standard.bool(forKey: "Print LogsInLogFile") {
            destinations.append(Logger.Output.Stdout)
        }
        if UserDefaults.standard.bool(forKey: "logInConsole") {
            destinations.append(Logger.Output.File)
        }
        Logger.setDestinations(destinations)
        if Logger.setFileDestination(UserDefaults.standard.string(forKey: "logFilePath")) {
            // success
        }

        /* set the maximum level of log output */
        Logger.setMaxLevel(Logger.LogLevel(rawValue: UserDefaults.standard.integer(forKey: "LogLevel"))!)

        let i = UInt64(UserDefaults.standard.integer(forKey: "clearLogPeriods"))
        Logger.setLimitLogSize(i)

        if let tl = TimeLimit.init(rawValue: UserDefaults.standard.integer(forKey: "timeLimitLogger")) {
            Logger.shared.timeLimit = tl
        }
        if let date2 = UserDefaults.standard.object(forKey: "startDate") as? Date {
            Logger.shared.startDate = date2
        }
    }
}
