//
//  Logger.swift
//  Wired
//
//  Created by Paul Repain on 15/05/2019.
//  Copyright © 2019 Read-Write.fr. All rights reserved.
//

import Foundation

public protocol LoggerDelegate: class {
    func loggerDidOutput(logger: Logger, output: String)
}

public extension LoggerDelegate {
    func loggerDidOutput(logger: Logger, output: String) {
        
    }
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

        var description: String {
            switch self {
            case .FATAL:
                return "FATAL"
            case .NOTICE:
                return "NOTICE"
            case .INFO:
                return "INFO"
            case .VERBOSE:
                return "VERBOSE"
            case .DEBUG:
                return "DEBUG"
            case .WARNING:
                return "WARNING"
            case .ERROR:
                return "ERROR"
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
            return "DcmSwift"
        }
    }
    
    private static var shared = Logger()
    public static var delegate:LoggerDelegate? = nil
    
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
        }

        // managing different type of output (console or file)
        for output in outputs {
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
    }

    /**
     Write in file. Creates a file if the file doesn't exist. Append at
     the end of the file.
     - parameter message: the log to be written in the file
     - returns: true if filepath is correct

     */
    public func fileLog(message: String) -> Bool {
        if let fileURL = filePath {

            if getFileSize() > self.sizeLimit {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                }
                catch {}
            }
            Logger.eraseFileByTime()

            var isDirectory = ObjCBool(true)
            // if file doesn't exist we create it
            if !FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) {
                FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
            }

            do {
                if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
                    fileHandle.seekToEndOfFile()
                    let data:Data = message.data(using: String.Encoding.utf8, allowLossyConversion: false)!
                    fileHandle.write(data)
                } else {
                    try message.write(to: fileURL, atomically: false, encoding: .utf8)
                }
            }
            catch {/* error handling here */}

            return true
        }
        return false
    }


    /**
     Set the destination for output : file (with name of file), console.
     Default log file is dicom.log
     - parameter destinations: all the destinations where the logs are outputted
     - parameter filePath: path of the logfile

     */
    public static func setDestinations(_ destinations: [Output], filePath: String? = nil) {
        shared.outputs = destinations
        if let fileName:String = filePath {
            shared.fileName = fileName
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

        if !path.contains(self.shared.fileName) {
            path += "/" + self.shared.fileName
        }
        shared.filePath = URL(fileURLWithPath: path)

        return true
    }


    /**
     Set the level of logs printed
     - parameter at: the log level to be set

     */
    public static func setMaxLevel(_ at: LogLevel) {
        if 0 <= at.rawValue && at.rawValue <= 5 {
            shared.maxLevel = at.rawValue
        }
    }

    public static func setLimitLogSize(_ at: UInt64) {
        shared.sizeLimit = at
    }

    public static func addDestination(_ dest: Output) {
        shared.outputs.append(dest)
    }

    public static func removeDestination(_ dest: Output) {
        shared.outputs = shared.outputs.filter{$0 != dest}
    }

    public static func setTimeLimit(_ at: TimeLimit) {
        shared.timeLimit = at
        shared.startDate = Date()/* the date is reset */
        UserDefaults.standard.set(shared.startDate, forKey: "startDate")
    }

    /**
     Erase the log file

     */
    public static func eraseFileByTime() {
        let range = -Int(shared.startDate.timeIntervalSinceNow)
        let t:Int

        switch shared.timeLimit {
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
            if let path = shared.filePath {
                Logger.removeLogFile(path)
                shared.startDate = Date()
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


    private func getFileSize() -> UInt64 {
        var fileSize : UInt64 = 0

        do {
            if let path = filePath?.path {
                let attr = try FileManager.default.attributesOfItem(atPath: path)
                fileSize = attr[FileAttributeKey.size] as! UInt64

                //if you convert to NSDictionary, you can get file size old way as well.
                let dict = attr as NSDictionary
                fileSize = dict.fileSize()
            }
        } catch {
            print("Error: \(error)")
        }

        return fileSize
    }

    public static func getSizeLimit() -> UInt64 {
        return shared.sizeLimit
    }


    public static func getFileDestination() -> String? {
        return shared.filePath?.path
    }

    public static func getTimeLimit() -> Int {
        return shared.timeLimit.rawValue
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
