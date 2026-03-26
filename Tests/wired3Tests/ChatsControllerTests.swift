import XCTest
@testable import wired3Lib

final class ChatsControllerTests: XCTestCase {
    func testNextChatIDSkipsExistingIDs() throws {
        let controller = try makeController()
        controller.add(chat: Chat(chatID: 2))

        XCTAssertEqual(controller.nextChatID(), 3)
    }

    func testAddAndRemoveMaintainPublicAndPrivateCollections() throws {
        let controller = try makeController()
        let publicChat = Chat(chatID: 10)
        let privateChat = PrivateChat(chatID: 11)

        controller.add(chat: publicChat)
        controller.add(chat: privateChat)
        XCTAssertEqual(controller.publicChats.count, 1)
        XCTAssertEqual(controller.privateChats.count, 1)
        XCTAssertNotNil(controller.chat(withID: 10))
        XCTAssertNotNil(controller.chat(withID: 11))

        controller.remove(chat: publicChat)
        controller.remove(chat: privateChat)
        XCTAssertEqual(controller.publicChats.count, 0)
        XCTAssertEqual(controller.privateChats.count, 0)
        XCTAssertNil(controller.chat(withID: 10))
        XCTAssertNil(controller.chat(withID: 11))
    }

    func testTypingPulseRateLimitTriggersOnFifthEventWithinOneSecond() throws {
        let controller = try makeController()
        let now = Date()

        XCTAssertFalse(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
        XCTAssertFalse(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
        XCTAssertFalse(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
        XCTAssertFalse(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
        XCTAssertTrue(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
    }

    func testUpdateTypingStateStartAndStopLifecycle() throws {
        let controller = try makeController()

        XCTAssertTrue(controller.updateTypingState(chatID: 1, userID: 5, isTyping: true))
        XCTAssertTrue(controller.updateTypingState(chatID: 1, userID: 5, isTyping: false))
        XCTAssertFalse(controller.updateTypingState(chatID: 1, userID: 5, isTyping: false))
    }

    func testExpireTypingStatesKeepsFreshState() throws {
        let controller = try makeController()
        XCTAssertTrue(controller.updateTypingState(chatID: 2, userID: 9, isTyping: true))

        controller.expireTypingStates()

        XCTAssertTrue(controller.updateTypingState(chatID: 2, userID: 9, isTyping: false))
    }

    private func makeController() throws -> ChatsController {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let databaseController = makeDatabaseController(tempDir: tempDir)
        return ChatsController(databaseController: databaseController)
    }
}
