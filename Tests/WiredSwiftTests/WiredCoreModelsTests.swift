import Foundation
import XCTest
@testable import WiredSwift

final class WiredCoreModelsTests: XCTestCase {
    func testThreadNameIsNeverEmpty() {
        XCTAssertFalse(Thread.current.threadName.isEmpty)
    }

    func testThreadNameIncludesOperationQueueWhenAvailable() {
        let expectation = expectation(description: "thread name")
        let queue = OperationQueue()
        queue.name = "WiredSwiftTestsQueue"
        var captured = ""

        queue.addOperation {
            captured = Thread.current.threadName
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        XCTAssertFalse(captured.isEmpty)
    }

    func testWiredErrorFromSpecErrorUsesNameAndDescription() {
        let spec = P7Spec(withPath: nil)
        let specError = SpecError(
            name: "wired.error.permission_denied",
            spec: spec,
            attributes: ["id": "4", "description": "Permission denied"]
        )

        let error = WiredError(withSPecError: specError)
        XCTAssertEqual(error.title, "wired.error.permission_denied")
        XCTAssertEqual(error.message, "[4] wired.error.permission_denied")
        XCTAssertTrue(error.description.contains("wired.error.permission_denied"))
    }

    func testWiredErrorFromTitleAndMessage() {
        let error = WiredError(withTitle: "Oops", message: "Something broke")
        XCTAssertEqual(error.title, "Oops")
        XCTAssertEqual(error.message, "Something broke")
        XCTAssertEqual(error.description, "Oops: Something broke")
    }

    func testWiredErrorFromProtocolMessage() {
        let message = P7Message(withName: "wired.error", spec: P7Spec(withPath: nil))
        message.addParameter(field: "wired.error.string", value: "Bad request")

        let error = WiredError(message: message)
        XCTAssertEqual(error.title, "Server Error")
        XCTAssertEqual(error.message, "Bad request")
    }

    func testWiredLogLevelPresentationProperties() {
        XCTAssertEqual(WiredLogLevel.debug.title, "Debug")
        XCTAssertEqual(WiredLogLevel.info.systemImageName, "info.circle")
        XCTAssertEqual(WiredLogLevel.warning.color, "yellow")
        XCTAssertEqual(WiredLogLevel.error.rawValue, 3)
        XCTAssertTrue(WiredLogLevel.debug < WiredLogLevel.error)
    }

    func testWiredLogEntryDecodesFromMessage() {
        let message = P7Message(withName: "wired.log.list", spec: P7Spec(withPath: nil))
        let now = Date()
        message.addParameter(field: "wired.log.time", value: now)
        message.addParameter(field: "wired.log.level", value: UInt32(2))
        message.addParameter(field: "wired.log.message", value: "watch out")

        let entry = WiredLogEntry(message: message)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.time, now)
        XCTAssertEqual(entry?.level, .warning)
        XCTAssertEqual(entry?.message, "watch out")
        XCTAssertTrue(entry?.id.contains("watch out") == true)
    }

    func testWiredLogEntryFailsWhenRequiredFieldMissingOrInvalid() {
        let missingField = P7Message(withName: "wired.log.list", spec: P7Spec(withPath: nil))
        XCTAssertNil(WiredLogEntry(message: missingField))

        let invalidLevel = P7Message(withName: "wired.log.list", spec: P7Spec(withPath: nil))
        invalidLevel.addParameter(field: "wired.log.time", value: Date())
        invalidLevel.addParameter(field: "wired.log.level", value: UInt32(99))
        invalidLevel.addParameter(field: "wired.log.message", value: "bad")
        XCTAssertNil(WiredLogEntry(message: invalidLevel))
    }

    func testWiredServerEventCategoryPresentationIsStable() {
        XCTAssertEqual(WiredServerEventCategory.users.title, "Users")
        XCTAssertEqual(WiredServerEventCategory.files.systemImageName, "folder.fill")
        XCTAssertEqual(Set(WiredServerEventCategory.allCases).count, 9)
    }

    func testWiredServerEventsExposeProtocolNameAndFormattedMessage() {
        for event in WiredServerEvent.allCases {
            XCTAssertTrue(event.protocolName.hasPrefix("wired.event."))
            XCTAssertFalse(event.formattedMessage(parameters: []).isEmpty)
        }
    }

    func testWiredServerEventFormattedMessageUsesDetailedParameters() {
        let moved = WiredServerEvent.fileMoved.formattedMessage(parameters: ["/a", "/b"])
        XCTAssertEqual(moved, "Moved \"/a\" to \"/b\"")

        let threadMoved = WiredServerEvent.boardMovedThread.formattedMessage(parameters: ["subject", "old", "new"])
        XCTAssertTrue(threadMoved.contains("\"old\""))
        XCTAssertTrue(threadMoved.contains("\"new\""))

        let completedDownload = WiredServerEvent.transferCompletedFileDownload
            .formattedMessage(parameters: ["/f.dat", "2048"])
        XCTAssertTrue(completedDownload.contains("/f.dat"))
        XCTAssertTrue(completedDownload.contains("after sending"))
    }

    func testWiredServerEventRecordDecodesAndComputesDerivedFields() throws {
        let message = P7Message(withName: "wired.event.event_list", spec: P7Spec(withPath: nil))
        let now = Date()
        message.addParameter(field: "wired.event.event", value: WiredServerEvent.boardSearched.rawValue)
        message.addParameter(field: "wired.event.time", value: now)
        message.addParameter(field: "wired.event.parameters", value: ["needle"])
        message.addParameter(field: "wired.user.nick", value: "nick")
        message.addParameter(field: "wired.user.login", value: "login")
        message.addParameter(field: "wired.user.ip", value: "127.0.0.1")

        let record = try XCTUnwrap(WiredServerEventRecord(message: message))
        XCTAssertEqual(record.time, now)
        XCTAssertEqual(record.event, .boardSearched)
        XCTAssertEqual(record.category, .boards)
        XCTAssertEqual(record.protocolName, "wired.event.board.searched")
        XCTAssertFalse(record.id.isEmpty)
    }

    func testWiredServerEventRecordUsesFallbackForUnknownEventCode() {
        let record = WiredServerEventRecord(
            eventCode: 999,
            time: Date(timeIntervalSince1970: 1),
            parameters: ["a", "b"],
            nick: "n",
            login: "l",
            ip: "1.2.3.4"
        )

        XCTAssertNil(record.event)
        XCTAssertEqual(record.category, .administration)
        XCTAssertEqual(record.protocolName, "wired.event.unknown.999")
        XCTAssertTrue(record.messageText.contains("wired.event.unknown.999"))
    }

    func testServerInfoParsesFieldsAndComputedProperties() {
        let message = P7Message(withName: "wired.server_info", spec: P7Spec(withPath: nil))
        message.addParameter(field: "wired.info.application.name", value: "Wired Server 3")
        message.addParameter(field: "wired.info.application.version", value: "3.0")
        message.addParameter(field: "wired.info.application.build", value: "28")
        message.addParameter(field: "wired.info.os.name", value: "macOS")
        message.addParameter(field: "wired.info.os.version", value: "14.0")
        message.addParameter(field: "wired.info.arch", value: "arm64")
        message.addParameter(field: "wired.info.supports_rsrc", value: UInt8(1))
        message.addParameter(field: "wired.info.name", value: "Server Name")
        message.addParameter(field: "wired.info.description", value: "Desc")
        message.addParameter(field: "wired.info.banner", value: Data([0x01, 0x02]))
        message.addParameter(field: "wired.info.start_time", value: Date(timeIntervalSince1970: 123))
        message.addParameter(field: "wired.info.files.count", value: UInt64(10))
        message.addParameter(field: "wired.info.files.size", value: UInt64(2048))

        let info = ServerInfo(message: message)
        XCTAssertEqual(info.applicationName, "Wired Server 3")
        XCTAssertEqual(info.serverVersion, "3.0 (28)")
        XCTAssertEqual(info.hostInfo, "macOS 14.0 (arm64)")
        XCTAssertEqual(info.supportRSRC, true)
        XCTAssertEqual(info.serverName, "Server Name")
        XCTAssertEqual(info.filesCount, 10)
        XCTAssertEqual(info.filesSize, 2048)
    }

    func testUserInfoParsesAndUpdateKeepsPreviousValuesWhenFieldsMissing() {
        let first = P7Message(withName: "wired.user.info", spec: P7Spec(withPath: nil))
        first.addParameter(field: "wired.user.id", value: UInt32(42))
        first.addParameter(field: "wired.user.idle", value: UInt8(1))
        first.addParameter(field: "wired.user.nick", value: "nick")
        first.addParameter(field: "wired.user.status", value: "status")
        first.addParameter(field: "wired.user.icon", value: Data([0xAA]))
        first.addParameter(field: "wired.account.color", value: UInt32(7))

        let info = UserInfo(message: first)
        XCTAssertEqual(info.userID, 42)
        XCTAssertEqual(info.idle, true)
        XCTAssertEqual(info.nick, "nick")
        XCTAssertEqual(info.status, "status")
        XCTAssertEqual(info.color, 7)
        XCTAssertEqual(info.description, "42:nick")

        let second = P7Message(withName: "wired.user.info", spec: P7Spec(withPath: nil))
        second.addParameter(field: "wired.user.nick", value: "updated")
        info.update(withMessage: second)

        XCTAssertEqual(info.userID, 42, "Missing field should keep previous value")
        XCTAssertEqual(info.nick, "updated")
        XCTAssertEqual(info.status, "status")
    }
}
