import XCTest
@testable import wired3Lib

final class ChatTests: XCTestCase {
    func testChatAddsAndRemovesClients() {
        let chat = Chat(chatID: 42)
        let client = makeClient(userID: 7)

        XCTAssertNil(chat.client(withID: client.userID))
        chat.addClient(client)
        XCTAssertNotNil(chat.client(withID: client.userID))

        chat.removeClient(client.userID)
        XCTAssertNil(chat.client(withID: client.userID))
    }

    func testPrivateChatInvitationLifecycle() {
        let privateChat = PrivateChat(chatID: 100)
        let invited = makeClient(userID: 11)

        XCTAssertFalse(privateChat.isInvited(client: invited))
        privateChat.addInvitation(client: invited)
        XCTAssertTrue(privateChat.isInvited(client: invited))

        privateChat.removeInvitation(client: invited)
        XCTAssertFalse(privateChat.isInvited(client: invited))
    }
}
