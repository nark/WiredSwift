import XCTest
@testable import WiredSwift

final class LoggerTests: XCTestCase {

    // MARK: - LogLevel.fromString

    func testFromStringFatal() {
        XCTAssertEqual(Logger.LogLevel.fromString("fatal"), .FATAL)
    }

    func testFromStringError() {
        XCTAssertEqual(Logger.LogLevel.fromString("error"), .ERROR)
    }

    func testFromStringWarning() {
        XCTAssertEqual(Logger.LogLevel.fromString("warning"), .WARNING)
    }

    func testFromStringWarnAlias() {
        XCTAssertEqual(Logger.LogLevel.fromString("warn"), .WARNING)
    }

    func testFromStringNotice() {
        XCTAssertEqual(Logger.LogLevel.fromString("notice"), .NOTICE)
    }

    func testFromStringInfo() {
        XCTAssertEqual(Logger.LogLevel.fromString("info"), .INFO)
    }

    func testFromStringDebug() {
        XCTAssertEqual(Logger.LogLevel.fromString("debug"), .DEBUG)
    }

    func testFromStringVerbose() {
        XCTAssertEqual(Logger.LogLevel.fromString("verbose"), .VERBOSE)
    }

    func testFromStringCaseInsensitive() {
        XCTAssertEqual(Logger.LogLevel.fromString("INFO"), .INFO)
        XCTAssertEqual(Logger.LogLevel.fromString("Warning"), .WARNING)
        XCTAssertEqual(Logger.LogLevel.fromString("DEBUG"), .DEBUG)
        XCTAssertEqual(Logger.LogLevel.fromString("WARN"), .WARNING)
    }

    func testFromStringWithLeadingTrailingSpaces() {
        XCTAssertEqual(Logger.LogLevel.fromString("  info  "), .INFO)
    }

    func testFromStringUnknownReturnsNil() {
        XCTAssertNil(Logger.LogLevel.fromString("garbage"))
        XCTAssertNil(Logger.LogLevel.fromString(""))
        XCTAssertNil(Logger.LogLevel.fromString("trace"))
    }

    // MARK: - LogLevel.description

    func testLogLevelDescriptions() {
        XCTAssertEqual(Logger.LogLevel.FATAL.description,   "FATAL")
        XCTAssertEqual(Logger.LogLevel.ERROR.description,   "ERROR")
        XCTAssertEqual(Logger.LogLevel.WARNING.description, "WARNING")
        XCTAssertEqual(Logger.LogLevel.NOTICE.description,  "NOTICE")
        XCTAssertEqual(Logger.LogLevel.INFO.description,    "INFO")
        XCTAssertEqual(Logger.LogLevel.DEBUG.description,   "DEBUG")
        XCTAssertEqual(Logger.LogLevel.VERBOSE.description, "VERBOSE")
    }

    // MARK: - LogLevel raw values (ordering)

    func testLogLevelRawValueOrdering() {
        // Lower rawValue = higher severity
        XCTAssertLessThan(Logger.LogLevel.FATAL.rawValue, Logger.LogLevel.ERROR.rawValue)
        XCTAssertLessThan(Logger.LogLevel.ERROR.rawValue, Logger.LogLevel.WARNING.rawValue)
        XCTAssertLessThan(Logger.LogLevel.WARNING.rawValue, Logger.LogLevel.INFO.rawValue)
        XCTAssertLessThan(Logger.LogLevel.INFO.rawValue, Logger.LogLevel.DEBUG.rawValue)
        XCTAssertLessThan(Logger.LogLevel.DEBUG.rawValue, Logger.LogLevel.VERBOSE.rawValue)
    }

    // MARK: - setMaxLevel / currentLevel round-trip

    func testSetMaxLevelRoundTrip() {
        Logger.setMaxLevel(.DEBUG)
        XCTAssertEqual(Logger.currentLevel, .DEBUG)

        Logger.setMaxLevel(.WARNING)
        XCTAssertEqual(Logger.currentLevel, .WARNING)

        Logger.setMaxLevel(.INFO)
        XCTAssertEqual(Logger.currentLevel, .INFO)
    }
}
