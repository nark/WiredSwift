import XCTest
@testable import WiredSwift

final class LoggerRuntimeTests: XCTestCase {
    private var originalLevel: Logger.LogLevel = .INFO
    private var originalSizeLimit: UInt64 = 0
    private var originalTimeLimit: Int = 0
    private var originalFileDestination: String?

    override func setUp() {
        super.setUp()
        originalLevel = Logger.currentLevel
        originalSizeLimit = Logger.getSizeLimit()
        originalTimeLimit = Logger.getTimeLimit()
        originalFileDestination = Logger.getFileDestination()
        Logger.delegate = nil
    }

    override func tearDown() {
        Logger.setDestinations([.Stdout])
        Logger.setMaxLevel(originalLevel)
        Logger.setLimitLogSize(originalSizeLimit)
        if let limit = Logger.TimeLimit(rawValue: originalTimeLimit) {
            Logger.setTimeLimit(limit)
        }
        if let originalFileDestination {
            _ = Logger.setFileDestination(originalFileDestination)
        }
        Logger.delegate = nil
        super.tearDown()
    }

    func testSetFileDestinationNilReturnsFalse() {
        XCTAssertFalse(Logger.setFileDestination(nil))
    }

    func testSetFileDestinationAppendsDefaultFileNameWhenDirectoryProvided() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(Logger.setFileDestination(directory.path))
        let resolved = try XCTUnwrap(Logger.getFileDestination())
        XCTAssertTrue(resolved.hasPrefix(directory.path))
        XCTAssertTrue(resolved.hasSuffix(".log"))
    }

    func testFileDestinationRoundTripWithExplicitPath() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultLogName = URL(fileURLWithPath: Logger.getFileDestination() ?? "xctest.log").lastPathComponent
        let explicitPath = directory.appendingPathComponent(defaultLogName).path

        XCTAssertTrue(Logger.setFileDestination(explicitPath))
        XCTAssertEqual(Logger.getFileDestination(), explicitPath)
    }

    func testFileLoggingWritesMessageToDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(Logger.setFileDestination(directory.path))
        let filePath = try XCTUnwrap(Logger.getFileDestination())
        Logger.setDestinations([.File])
        Logger.setMaxLevel(.VERBOSE)

        let marker = "LOGGER_FILE_WRITE_MARKER"
        Logger.info(marker, "tests")

        let contents = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertTrue(contents.contains(marker))
        XCTAssertTrue(contents.contains("INFO"))
        XCTAssertTrue(contents.contains("[tests]"))
    }

    func testFileLogRotationBySizeRemovesOldContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(Logger.setFileDestination(directory.path))
        let filePath = try XCTUnwrap(Logger.getFileDestination())
        Logger.setDestinations([.File])
        Logger.setMaxLevel(.VERBOSE)
        Logger.setLimitLogSize(1_000_000)

        let firstMarker = "FIRST_MARKER_ROTATION"
        Logger.info(firstMarker, "tests")
        XCTAssertTrue(try String(contentsOfFile: filePath, encoding: .utf8).contains(firstMarker))

        Logger.setLimitLogSize(1)
        let secondMarker = "SECOND_MARKER_ROTATION"
        Logger.info(secondMarker, "tests")

        let rotatedContent = try String(contentsOfFile: filePath, encoding: .utf8)
        XCTAssertFalse(rotatedContent.contains(firstMarker))
        XCTAssertTrue(rotatedContent.contains(secondMarker))
    }

    func testDelegateReceivesStructuredAndFormattedCallbacks() {
        let delegate = CapturingLoggerDelegate()
        Logger.delegate = delegate
        Logger.setDestinations([])
        Logger.setMaxLevel(.VERBOSE)

        Logger.warning("delegate-message", "unit-tests")

        XCTAssertEqual(delegate.entries.count, 1)
        XCTAssertEqual(delegate.entries.first?.level, .WARNING)
        XCTAssertEqual(delegate.entries.first?.message, "delegate-message")
        XCTAssertEqual(delegate.formattedOutputs.count, 1)
        XCTAssertTrue(delegate.formattedOutputs[0].contains("delegate-message"))
    }

    func testPreferencesAreAppliedFromUserDefaults() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults.standard

        defaults.set(true, forKey: "Print LogsInLogFile")
        defaults.set(true, forKey: "logInConsole")
        defaults.set(directory.path, forKey: "logFilePath")
        defaults.set(Logger.LogLevel.ERROR.rawValue, forKey: "LogLevel")
        defaults.set(777, forKey: "clearLogPeriods")
        defaults.set(Logger.TimeLimit.Day.rawValue, forKey: "timeLimitLogger")
        defaults.set(Date(timeIntervalSince1970: 123), forKey: "startDate")

        Logger.setPreferences()

        XCTAssertEqual(Logger.currentLevel, .ERROR)
        XCTAssertEqual(Logger.getSizeLimit(), 777)
        XCTAssertEqual(Logger.getTimeLimit(), Logger.TimeLimit.Day.rawValue)
        XCTAssertNotNil(Logger.getFileDestination())
    }
}

private final class CapturingLoggerDelegate: LoggerDelegate {
    struct Entry {
        let level: Logger.LogLevel
        let message: String
        let date: Date
    }

    var entries: [Entry] = []
    var formattedOutputs: [String] = []

    func loggerDidOutput(logger: Logger, output: String) {
        formattedOutputs.append(output)
    }

    func loggerDidLog(level: Logger.LogLevel, message: String, date: Date) {
        entries.append(Entry(level: level, message: message, date: date))
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wiredswift-logger-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
