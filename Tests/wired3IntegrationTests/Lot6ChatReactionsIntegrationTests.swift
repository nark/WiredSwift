import XCTest
import WiredSwift
@testable import wired3Lib

/// End-to-end test for Wired 3.2 chat reactions.
///
/// Exercises the full flow:
///   1. send_say → server stamps `wired.chat.message.id` on the broadcast
///   2. add_reaction → broadcast `reaction_added` to peers
///   3. get_reactions → enumerated `reaction_list` entries
///   4. remove_reaction → broadcast `reaction_removed`
final class Lot6ChatReactionsIntegrationTests: SerializedIntegrationTestCase {

    func testChatReactionsRoundTrip() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let c1 = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { c1.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: c1)
        _ = try sendLoginAndExpectSuccess(socket: c1, username: "it_admin", password: "secret")
        drainMessages(socket: c1)

        let c2 = try runtime.connectClient(username: "it_admin_2", password: "secret2")
        defer { c2.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: c2)
        _ = try sendLoginAndExpectSuccess(socket: c2, username: "it_admin_2", password: "secret2")
        drainMessages(socket: c2)

        // Both join the default public chat (id 1).
        let chatID: UInt32 = 1
        for s in [c1, c2] {
            let join = P7Message(withName: "wired.chat.join_chat", spec: s.spec)
            join.addParameter(field: "wired.chat.id", value: chatID)
            XCTAssertTrue(s.write(join))
            _ = try readMessage(from: s, expectedName: "wired.chat.user_list.done", maxReads: 30)
            _ = try readMessage(from: s, expectedName: "wired.chat.topic", maxReads: 30)
        }
        // Drain the user_join broadcast c1 sees from c2.
        _ = tryReadMessage(from: c1, expectedNames: ["wired.chat.user_join"], maxReads: 40, timeout: 0.25)

        // c1 sends a message and learns its server-stamped id from the broadcast.
        let say = P7Message(withName: "wired.chat.send_say", spec: c1.spec)
        say.addParameter(field: "wired.chat.id", value: chatID)
        say.addParameter(field: "wired.chat.say", value: "hello reactions")
        XCTAssertTrue(c1.write(say))
        _ = try readMessage(from: c1, expectedName: "wired.okay", maxReads: 20)
        let sayBroadcast = try readMessage(from: c1, expectedName: "wired.chat.say", maxReads: 30)
        let messageID = try XCTUnwrap(sayBroadcast.string(forField: "wired.chat.message.id"),
                                      "Server must stamp wired.chat.message.id on public-chat say")
        XCTAssertFalse(messageID.isEmpty)

        // c2 should see the same broadcast with the same id (drain to it).
        let c2Say = try readMessage(from: c2, expectedName: "wired.chat.say", maxReads: 30)
        XCTAssertEqual(c2Say.string(forField: "wired.chat.message.id"), messageID)

        // c2 reacts. Expect okay + reaction_added broadcast on both ends.
        let add = P7Message(withName: "wired.chat.add_reaction", spec: c2.spec)
        add.addParameter(field: "wired.chat.id", value: chatID)
        add.addParameter(field: "wired.chat.message.id", value: messageID)
        add.addParameter(field: "wired.chat.reaction.emoji", value: "👍")
        XCTAssertTrue(c2.write(add))
        _ = try readMessage(from: c2, expectedName: "wired.okay", maxReads: 20)

        let added = try readMessage(from: c1, expectedName: "wired.chat.reaction_added", maxReads: 40)
        XCTAssertEqual(added.string(forField: "wired.chat.message.id"), messageID)
        XCTAssertEqual(added.string(forField: "wired.chat.reaction.emoji"), "👍")
        XCTAssertEqual(added.uint32(forField: "wired.chat.reaction.count"), 1)
        XCTAssertEqual(added.string(forField: "wired.chat.reaction.nick"), "it_admin_2")

        // c1 fetches the reaction list and checks isOwn=false (c1 didn't react).
        let get = P7Message(withName: "wired.chat.get_reactions", spec: c1.spec)
        get.addParameter(field: "wired.chat.id", value: chatID)
        get.addParameter(field: "wired.chat.message.id", value: messageID)
        XCTAssertTrue(c1.write(get))
        let list = try readMessage(from: c1, expectedName: "wired.chat.reaction_list", maxReads: 30)
        XCTAssertEqual(list.string(forField: "wired.chat.reaction.emoji"), "👍")
        XCTAssertEqual(list.uint32(forField: "wired.chat.reaction.count"), 1)
        XCTAssertEqual(list.bool(forField: "wired.chat.reaction.is_own"), false)
        _ = try readMessage(from: c1, expectedName: "wired.okay", maxReads: 10)

        // c2 removes its reaction; c1 sees reaction_removed.
        let remove = P7Message(withName: "wired.chat.remove_reaction", spec: c2.spec)
        remove.addParameter(field: "wired.chat.id", value: chatID)
        remove.addParameter(field: "wired.chat.message.id", value: messageID)
        remove.addParameter(field: "wired.chat.reaction.emoji", value: "👍")
        XCTAssertTrue(c2.write(remove))
        _ = try readMessage(from: c2, expectedName: "wired.okay", maxReads: 20)
        let removed = try readMessage(from: c1, expectedName: "wired.chat.reaction_removed", maxReads: 30)
        XCTAssertEqual(removed.string(forField: "wired.chat.message.id"), messageID)
        XCTAssertEqual(removed.uint32(forField: "wired.chat.reaction.count"), 0)

        // Reacting on an unknown id surfaces invalid_message.
        let bogus = P7Message(withName: "wired.chat.add_reaction", spec: c2.spec)
        bogus.addParameter(field: "wired.chat.id", value: chatID)
        bogus.addParameter(field: "wired.chat.message.id", value: "00000000-0000-0000-0000-000000000000")
        bogus.addParameter(field: "wired.chat.reaction.emoji", value: "🚫")
        XCTAssertTrue(c2.write(bogus))
        let err = try readMessage(from: c2, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(err.enumeration(forField: "wired.error"), 1) // invalid_message
    }

    /// Mirrors the manual test plan from PR #89: synthesize a "3.1" spec by
    /// stripping every 3.2 chat reaction item from the bundled XML and verify
    /// the compatibility diff identifies what a 3.2 sender would have to drop
    /// when speaking to a 3.1 peer.
    func testCompatibilityDiffStripsChatReactionItemsFor31Peer() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/WiredSwift/Resources/wired.xml")
        let xml = try String(contentsOf: url, encoding: .utf8)
        let stripped = stripChatReactionsAndBumpTo31(xml)
        let local = try XCTUnwrap(P7Spec(withUrl: url))
        let remote = try XCTUnwrap(P7Spec(withString: stripped))
        let diff = CompatibilityDiff.diff(local: local, remote: remote)

        // The 3.2 chat reaction message ids (4033..4038) must show up as
        // unknown to the 3.1 peer; sender filtering will drop them.
        let droppedMessageIDs: [Int] = [4033, 4034, 4035, 4036, 4037, 4038]
        for id in droppedMessageIDs {
            XCTAssertTrue(diff.messagesUnknownToRemote.contains(UInt32(id)),
                          "Diff should mark message id \(id) as unknown to a stripped 3.1 peer")
        }
        XCTAssertTrue(diff.fieldsUnknownToRemote.contains(4007),
                      "Diff should mark wired.chat.message.id (4007) as unknown to a stripped 3.1 peer")
    }

    private func stripChatReactionsAndBumpTo31(_ xml: String) -> String {
        var out = xml
        // Re-id every 3.2 chat reaction field/message/permission so they look
        // foreign to the diff; the actual XML structure is unchanged.
        let renames: [(String, String)] = [
            ("id=\"4007\" version=\"3.2\"", "id=\"99007\" version=\"3.2\""),
            ("id=\"4020\" version=\"3.2\"", "id=\"99020\" version=\"3.2\""),
            ("id=\"4021\" version=\"3.2\"", "id=\"99021\" version=\"3.2\""),
            ("id=\"4022\" version=\"3.2\"", "id=\"99022\" version=\"3.2\""),
            ("id=\"4023\" version=\"3.2\"", "id=\"99023\" version=\"3.2\""),
            ("id=\"4024\" version=\"3.2\"", "id=\"99024\" version=\"3.2\""),
            ("id=\"4025\" version=\"3.2\"", "id=\"99025\" version=\"3.2\""),
            ("id=\"4033\" version=\"3.2\"", "id=\"99033\" version=\"3.2\""),
            ("id=\"4034\" version=\"3.2\"", "id=\"99034\" version=\"3.2\""),
            ("id=\"4035\" version=\"3.2\"", "id=\"99035\" version=\"3.2\""),
            ("id=\"4036\" version=\"3.2\"", "id=\"99036\" version=\"3.2\""),
            ("id=\"4037\" version=\"3.2\"", "id=\"99037\" version=\"3.2\""),
            ("id=\"4038\" version=\"3.2\"", "id=\"99038\" version=\"3.2\""),
        ]
        for (from, to) in renames {
            out = out.replacingOccurrences(of: from, with: to)
        }
        return out
    }
}
