import XCTest
@testable import wired3Lib

final class ChatsControllerTests: XCTestCase {
    func testDescribeReturnsExpectedKindAndName() throws {
        let controller = try makeController()
        let publicDescription = controller.describe(chat: Chat(chatID: 42, name: "General", client: nil))
        let privateDescription = controller.describe(chat: PrivateChat(chatID: 43))

        XCTAssertTrue(publicDescription.contains("kind=public"))
        XCTAssertTrue(publicDescription.contains("chatID=42"))
        XCTAssertTrue(publicDescription.contains("name='General'"))

        XCTAssertTrue(privateDescription.contains("kind=private"))
        XCTAssertTrue(privateDescription.contains("chatID=43"))
        XCTAssertTrue(privateDescription.contains("name='Private Chat'"))
    }

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

    func testAddWithDuplicateIDReplacesChatTypeCollections() throws {
        let controller = try makeController()
        controller.add(chat: Chat(chatID: 7))
        controller.add(chat: PrivateChat(chatID: 7))

        XCTAssertEqual(controller.publicChats.count, 0)
        XCTAssertEqual(controller.privateChats.count, 1)
        XCTAssertTrue(controller.chat(withID: 7) is PrivateChat)
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

    func testTypingPulseRateLimitResetsAfterWindow() throws {
        let controller = try makeController()
        let now = Date()

        for _ in 0..<4 {
            XCTAssertFalse(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
        }
        XCTAssertTrue(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now))
        XCTAssertFalse(controller.shouldRateLimitTypingPulse(chatID: 1, userID: 1, now: now.addingTimeInterval(1.1)))
    }

    func testUpdateTypingStateStartAndStopLifecycle() throws {
        let controller = try makeController()

        XCTAssertTrue(controller.updateTypingState(chatID: 1, userID: 5, isTyping: true))
        XCTAssertTrue(controller.updateTypingState(chatID: 1, userID: 5, isTyping: false))
        XCTAssertFalse(controller.updateTypingState(chatID: 1, userID: 5, isTyping: false))
    }

    func testClearTypingStateForChatIDRemovesOnlyMatchingChat() throws {
        let controller = try makeController()
        XCTAssertTrue(controller.updateTypingState(chatID: 5, userID: 10, isTyping: true))
        XCTAssertTrue(controller.updateTypingState(chatID: 5, userID: 11, isTyping: true))
        XCTAssertTrue(controller.updateTypingState(chatID: 6, userID: 10, isTyping: true))

        controller.clearTypingState(forChatID: 5)

        XCTAssertFalse(controller.updateTypingState(chatID: 5, userID: 10, isTyping: false))
        XCTAssertFalse(controller.updateTypingState(chatID: 5, userID: 11, isTyping: false))
        XCTAssertTrue(controller.updateTypingState(chatID: 6, userID: 10, isTyping: false))
    }

    func testRemoveClearsTypingStateForRemovedChat() throws {
        let controller = try makeController()
        let chat = Chat(chatID: 9)
        controller.add(chat: chat)
        XCTAssertTrue(controller.updateTypingState(chatID: 9, userID: 1, isTyping: true))

        controller.remove(chat: chat)

        XCTAssertFalse(controller.updateTypingState(chatID: 9, userID: 1, isTyping: false))
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
