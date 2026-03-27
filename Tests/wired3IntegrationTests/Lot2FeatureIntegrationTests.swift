import XCTest
import WiredSwift

final class Lot2FeatureIntegrationTests: SerializedIntegrationTestCase {
    func testChatCreateJoinSayLeaveWithTwoClients() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let c1 = try runtime.connectClient(username: "it_admin", password: "secret")
        defer {
            c1.disconnect()
        }

        try sendClientInfoAndExpectServerInfo(socket: c1)
        let c1Login = try sendLoginAndExpectSuccess(socket: c1, username: "it_admin", password: "secret")
        let c1UserID = try XCTUnwrap(c1Login.uint32(forField: "wired.user.id"))
        drainMessages(socket: c1)

        let create = P7Message(withName: "wired.chat.create_public_chat", spec: c1.spec)
        create.addParameter(field: "wired.chat.name", value: "Integration Room")
        XCTAssertTrue(c1.write(create))

        _ = try readMessage(from: c1, expectedName: "wired.okay", maxReads: 40, timeout: 1)

        // CI can deliver broadcasts in different orders; resolve the chat ID from the
        // authoritative chat list instead of relying on public_chat_created timing.
        let getChats = P7Message(withName: "wired.chat.get_chats", spec: c1.spec)
        XCTAssertTrue(c1.write(getChats))

        var createdChatID: UInt32?
        for _ in 0..<60 {
            let message: P7Message
            do {
                message = try c1.readMessage(timeout: 1, enforceDeadline: true)
            } catch {
                continue
            }

            if message.name == "wired.chat.chat_list",
               message.string(forField: "wired.chat.name") == "Integration Room",
               let id = message.uint32(forField: "wired.chat.id") {
                createdChatID = id
            }

            if message.name == "wired.chat.chat_list.done" {
                break
            }
        }
        let resolvedChatID = try XCTUnwrap(
            createdChatID,
            "Expected created public chat to appear in wired.chat.get_chats listing"
        )

        let joinCreator = P7Message(withName: "wired.chat.join_chat", spec: c1.spec)
        joinCreator.addParameter(field: "wired.chat.id", value: resolvedChatID)
        XCTAssertTrue(c1.write(joinCreator))
        _ = try readMessage(from: c1, expectedName: "wired.chat.user_list.done", maxReads: 20)
        _ = try readMessage(from: c1, expectedName: "wired.chat.topic", maxReads: 20)

        XCTAssertTrue(
            waitUntil(timeout: 3) {
                runtime.chatMemberIDs(chatID: resolvedChatID) == Set([c1UserID])
            },
            "Creator should be present in the chat after join"
        )

        // Defer second connection until the chat exists and creator already joined,
        // which is less flaky on CI under strict identity/runtime timing.
        let c2 = try runtime.connectClient(username: "it_admin_2", password: "secret2")
        defer { c2.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: c2)
        let c2Login = try sendLoginAndExpectSuccess(socket: c2, username: "it_admin_2", password: "secret2")
        let c2UserID = try XCTUnwrap(c2Login.uint32(forField: "wired.user.id"))
        drainMessages(socket: c2)

        let join = P7Message(withName: "wired.chat.join_chat", spec: c2.spec)
        join.addParameter(field: "wired.chat.id", value: resolvedChatID)
        XCTAssertTrue(c2.write(join))
        _ = try readMessage(from: c2, expectedName: "wired.chat.user_list.done", maxReads: 20)
        _ = try readMessage(from: c2, expectedName: "wired.chat.topic", maxReads: 20)
        _ = tryReadMessage(from: c1, expectedNames: ["wired.chat.user_join"], maxReads: 80, timeout: 0.25)

        XCTAssertTrue(
            waitUntil(timeout: 3) {
                runtime.chatMemberIDs(chatID: resolvedChatID) == Set([c1UserID, c2UserID])
            },
            "Both clients should be present after second join"
        )

        let say = P7Message(withName: "wired.chat.send_say", spec: c2.spec)
        say.addParameter(field: "wired.chat.id", value: resolvedChatID)
        say.addParameter(field: "wired.chat.say", value: "hello integration")
        XCTAssertTrue(c2.write(say))
        _ = try readMessage(from: c2, expectedName: "wired.okay", maxReads: 20)
        _ = tryReadMessage(from: c1, expectedNames: ["wired.chat.say"], maxReads: 80, timeout: 0.25)

        let leave = P7Message(withName: "wired.chat.leave_chat", spec: c2.spec)
        leave.addParameter(field: "wired.chat.id", value: resolvedChatID)
        XCTAssertTrue(c2.write(leave))
        _ = try readMessage(from: c2, expectedName: "wired.okay", maxReads: 20)
        _ = tryReadMessage(from: c1, expectedNames: ["wired.chat.user_leave"], maxReads: 80, timeout: 0.25)

        XCTAssertTrue(
            waitUntil(timeout: 3) {
                runtime.chatMemberIDs(chatID: resolvedChatID) == Set([c1UserID])
            },
            "Second client should be removed from the chat after leave"
        )
    }

    func testFilesCreateMoveDeleteAndJailValidation() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let createDir = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
        createDir.addParameter(field: "wired.file.path", value: "/it_dir")
        XCTAssertTrue(socket.write(createDir))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)

        let list = P7Message(withName: "wired.file.list_directory", spec: socket.spec)
        list.addParameter(field: "wired.file.path", value: "/")
        XCTAssertTrue(socket.write(list))

        var sawDir = false
        for _ in 0..<32 {
            let message: P7Message
            do {
                message = try socket.readMessage(timeout: 3, enforceDeadline: true)
            } catch {
                continue
            }
            if message.name == "wired.file.file_list",
               message.string(forField: "wired.file.path") == "/it_dir" {
                sawDir = true
            }
            if message.name == "wired.file.file_list.done" {
                break
            }
        }
        XCTAssertTrue(sawDir)

        let move = P7Message(withName: "wired.file.move", spec: socket.spec)
        move.addParameter(field: "wired.file.path", value: "/it_dir")
        move.addParameter(field: "wired.file.new_path", value: "/it_dir2")
        XCTAssertTrue(socket.write(move))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)

        let delete = P7Message(withName: "wired.file.delete", spec: socket.spec)
        delete.addParameter(field: "wired.file.path", value: "/it_dir2")
        XCTAssertTrue(socket.write(delete))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 10)

        let traversal = P7Message(withName: "wired.file.get_info", spec: socket.spec)
        traversal.addParameter(field: "wired.file.path", value: "/../etc/passwd")
        XCTAssertTrue(socket.write(traversal))
        _ = try readMessage(from: socket, expectedName: "wired.error", maxReads: 10)
    }

    func testAccountsPermissionDeniedForGuestAndAllowedForPrivilegedUser() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let guest = try runtime.connectClient(username: "guest", password: "")
        defer { guest.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: guest)
        _ = try sendLoginAndExpectSuccess(socket: guest, username: "guest", password: "")
        drainMessages(socket: guest)

        let listUsers = P7Message(withName: "wired.account.list_users", spec: guest.spec)
        XCTAssertTrue(guest.write(listUsers))
        _ = try readMessage(from: guest, expectedName: "wired.error", maxReads: 10)

        let admin = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: admin)
        _ = try sendLoginAndExpectSuccess(socket: admin, username: "it_admin", password: "secret")
        drainMessages(socket: admin)

        let listUsersAdmin = P7Message(withName: "wired.account.list_users", spec: admin.spec)
        XCTAssertTrue(admin.write(listUsersAdmin))
        _ = try readMessage(from: admin, expectedName: "wired.account.user_list.done", maxReads: 30)

        let readUser = P7Message(withName: "wired.account.read_user", spec: admin.spec)
        readUser.addParameter(field: "wired.account.name", value: "guest")
        XCTAssertTrue(admin.write(readUser))
        _ = try readMessage(from: admin, expectedName: "wired.account.user", maxReads: 20)
    }

    func testBanlistBlocksLoginUntilRemoved() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let admin = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: admin)
        _ = try sendLoginAndExpectSuccess(socket: admin, username: "it_admin", password: "secret")
        drainMessages(socket: admin)

        let addBan = P7Message(withName: "wired.banlist.add_ban", spec: admin.spec)
        addBan.addParameter(field: "wired.banlist.ip", value: "127.0.0.1")
        XCTAssertTrue(admin.write(addBan))
        _ = try readMessage(from: admin, expectedName: "wired.okay", maxReads: 10)

        let blocked = try runtime.connectClient(username: "guest", password: "")
        defer { blocked.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: blocked)
        let denied = try sendLoginAndExpectError(socket: blocked, username: "guest", password: "")
        XCTAssertEqual(denied.name, "wired.banned")

        let deleteBan = P7Message(withName: "wired.banlist.delete_ban", spec: admin.spec)
        deleteBan.addParameter(field: "wired.banlist.ip", value: "127.0.0.1")
        XCTAssertTrue(admin.write(deleteBan))
        _ = try readMessage(from: admin, expectedName: "wired.okay", maxReads: 10)
    }

    func testEventAndLogCoverageWithSubscribeAndHistoryFetch() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let triggerEvent = P7Message(withName: "wired.account.list_users", spec: socket.spec)
        XCTAssertTrue(socket.write(triggerEvent))
        _ = try readMessage(from: socket, expectedName: "wired.account.user_list.done", maxReads: 60, timeout: 1)

        let getEvents = P7Message(withName: "wired.event.get_events", spec: socket.spec)
        getEvents.addParameter(field: "wired.event.last_event_count", value: UInt32(10))
        XCTAssertTrue(socket.write(getEvents))

        var sawEventList = false
        var sawEventListDone = false
        for _ in 0..<80 {
            let message: P7Message
            do {
                message = try socket.readMessage(timeout: 0.5, enforceDeadline: true)
            } catch {
                continue
            }
            if message.name == "wired.event.event_list" {
                sawEventList = true
            }
            if message.name == "wired.event.event_list.done" {
                sawEventListDone = true
                break
            }
        }
        XCTAssertTrue(sawEventList)
        XCTAssertTrue(sawEventListDone)

        let marker = "integration-log-\(UUID().uuidString)"
        Logger.info(marker)

        let getLog = P7Message(withName: "wired.log.get_log", spec: socket.spec)
        XCTAssertTrue(socket.write(getLog))

        var sawMarker = false
        var sawLogDone = false
        for _ in 0..<160 {
            let message: P7Message
            do {
                message = try socket.readMessage(timeout: 0.5, enforceDeadline: true)
            } catch {
                continue
            }
            if message.name == "wired.log.list",
               message.string(forField: "wired.log.message")?.contains(marker) == true {
                sawMarker = true
            }
            if message.name == "wired.log.list.done" {
                sawLogDone = true
                break
            }
        }
        XCTAssertTrue(sawLogDone)
        XCTAssertTrue(sawMarker)
    }

    func testAccountSubscribeUnsubscribeLifecycleReturnsExpectedErrors() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let subscribe = P7Message(withName: "wired.account.subscribe_accounts", spec: socket.spec)
        XCTAssertTrue(socket.write(subscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(subscribe))
        let already = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(already.string(forField: "wired.error.string"), "wired.error.already_subscribed")

        let unsubscribe = P7Message(withName: "wired.account.unsubscribe_accounts", spec: socket.spec)
        XCTAssertTrue(socket.write(unsubscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(unsubscribe))
        let notSubscribed = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(notSubscribed.string(forField: "wired.error.string"), "wired.error.not_subscribed")
    }

    func testEventSubscribeUnsubscribeLifecycleReturnsExpectedErrors() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let subscribe = P7Message(withName: "wired.event.subscribe", spec: socket.spec)
        XCTAssertTrue(socket.write(subscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(subscribe))
        let already = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(already.string(forField: "wired.error.string"), "wired.error.already_subscribed")

        let unsubscribe = P7Message(withName: "wired.event.unsubscribe", spec: socket.spec)
        XCTAssertTrue(socket.write(unsubscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(unsubscribe))
        let notSubscribed = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(notSubscribed.string(forField: "wired.error.string"), "wired.error.not_subscribed")
    }

    func testLogSubscribeUnsubscribeLifecycleReturnsExpectedErrors() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let subscribe = P7Message(withName: "wired.log.subscribe", spec: socket.spec)
        XCTAssertTrue(socket.write(subscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(subscribe))
        let already = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(already.string(forField: "wired.error.string"), "wired.error.already_subscribed")

        let unsubscribe = P7Message(withName: "wired.log.unsubscribe", spec: socket.spec)
        XCTAssertTrue(socket.write(unsubscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(unsubscribe))
        let notSubscribed = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(notSubscribed.string(forField: "wired.error.string"), "wired.error.not_subscribed")
    }

    func testAdminCreateReadAndDeleteUserLifecycle() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let createdUsername = "integration_user_\(UUID().uuidString.prefix(8))"

        let createUser = P7Message(withName: "wired.account.create_user", spec: socket.spec)
        createUser.addParameter(field: "wired.account.name", value: createdUsername)
        createUser.addParameter(field: "wired.account.password", value: "integration-secret")
        createUser.addParameter(field: "wired.account.full_name", value: "Integration User")
        createUser.addParameter(field: "wired.account.comment", value: "Created by integration test")
        XCTAssertTrue(socket.write(createUser))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let readCreated = P7Message(withName: "wired.account.read_user", spec: socket.spec)
        readCreated.addParameter(field: "wired.account.name", value: createdUsername)
        XCTAssertTrue(socket.write(readCreated))
        let created = try readMessage(from: socket, expectedName: "wired.account.user", maxReads: 20)
        XCTAssertEqual(created.string(forField: "wired.account.name"), createdUsername)

        let deleteUser = P7Message(withName: "wired.account.delete_user", spec: socket.spec)
        deleteUser.addParameter(field: "wired.account.name", value: createdUsername)
        deleteUser.addParameter(field: "wired.account.disconnect_users", value: UInt8(0))
        XCTAssertTrue(socket.write(deleteUser))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let readDeleted = P7Message(withName: "wired.account.read_user", spec: socket.spec)
        readDeleted.addParameter(field: "wired.account.name", value: createdUsername)
        XCTAssertTrue(socket.write(readDeleted))
        let missing = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(missing.string(forField: "wired.error.string"), "wired.error.account_not_found")
    }

    func testSettingsSetAndGetRoundTripForPrivilegedUser() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let marker = "Integration \(UUID().uuidString.prefix(6))"
        let set = P7Message(withName: "wired.settings.set_settings", spec: socket.spec)
        set.addParameter(field: "wired.info.name", value: marker)
        set.addParameter(field: "wired.info.description", value: "integration settings roundtrip")
        set.addParameter(field: "wired.info.downloads", value: UInt32(7))
        set.addParameter(field: "wired.info.uploads", value: UInt32(9))
        set.addParameter(field: "wired.info.download_speed", value: UInt32(11))
        set.addParameter(field: "wired.info.upload_speed", value: UInt32(13))
        set.addParameter(field: "wired.settings.register_with_trackers", value: UInt8(0))
        XCTAssertTrue(socket.write(set))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let get = P7Message(withName: "wired.settings.get_settings", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let settings = try readMessage(from: socket, expectedName: "wired.settings.settings", maxReads: 20)
        XCTAssertEqual(settings.string(forField: "wired.info.name"), marker)
        XCTAssertEqual(settings.string(forField: "wired.info.description"), "integration settings roundtrip")
        XCTAssertEqual(settings.uint32(forField: "wired.info.downloads"), UInt32(7))
        XCTAssertEqual(settings.uint32(forField: "wired.info.uploads"), UInt32(9))
        XCTAssertEqual(settings.uint32(forField: "wired.info.download_speed"), UInt32(11))
        XCTAssertEqual(settings.uint32(forField: "wired.info.upload_speed"), UInt32(13))
        XCTAssertEqual(settings.bool(forField: "wired.settings.register_with_trackers"), false)
    }

    func testSettingsSetDeniedForGuest() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "guest", password: "")
        drainMessages(socket: socket)

        let set = P7Message(withName: "wired.settings.set_settings", spec: socket.spec)
        set.addParameter(field: "wired.info.name", value: "Guest cannot set this")
        XCTAssertTrue(socket.write(set))
        let denied = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(denied.string(forField: "wired.error.string"), "wired.error.permission_denied")
    }

    func testBoardSubscribeUnsubscribeLifecycleReturnsExpectedErrors() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let subscribe = P7Message(withName: "wired.board.subscribe_boards", spec: socket.spec)
        XCTAssertTrue(socket.write(subscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(subscribe))
        let already = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(already.string(forField: "wired.error.string"), "wired.error.already_subscribed")

        let unsubscribe = P7Message(withName: "wired.board.unsubscribe_boards", spec: socket.spec)
        XCTAssertTrue(socket.write(unsubscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(unsubscribe))
        let notSubscribed = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(notSubscribed.string(forField: "wired.error.string"), "wired.error.not_subscribed")
    }

    func testFileSubscribeUnsubscribeLifecycleReturnsExpectedErrors() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let createDir = P7Message(withName: "wired.file.create_directory", spec: socket.spec)
        createDir.addParameter(field: "wired.file.path", value: "/watch_dir")
        XCTAssertTrue(socket.write(createDir))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        let subscribe = P7Message(withName: "wired.file.subscribe_directory", spec: socket.spec)
        subscribe.addParameter(field: "wired.file.path", value: "/watch_dir")
        XCTAssertTrue(socket.write(subscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        let unsubscribe = P7Message(withName: "wired.file.unsubscribe_directory", spec: socket.spec)
        unsubscribe.addParameter(field: "wired.file.path", value: "/watch_dir")
        XCTAssertTrue(socket.write(unsubscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        XCTAssertTrue(socket.write(unsubscribe))
        let notSubscribed = try readMessage(from: socket, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(notSubscribed.string(forField: "wired.error.string"), "wired.error.not_subscribed")
    }

    func testAccountsSubscriberReceivesAccountsChangedBroadcastOnCreateUser() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let subscriber = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { subscriber.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: subscriber)
        _ = try sendLoginAndExpectSuccess(socket: subscriber, username: "it_admin", password: "secret")
        drainMessages(socket: subscriber)

        let subscribe = P7Message(withName: "wired.account.subscribe_accounts", spec: subscriber.spec)
        XCTAssertTrue(subscriber.write(subscribe))
        _ = try readMessage(from: subscriber, expectedName: "wired.okay", maxReads: 12)

        let createdUsername = "integration_notify_\(UUID().uuidString.prefix(8))"
        // Use the same privileged socket as subscriber + creator to avoid
        // cross-connection timing races that can make this assertion flaky on CI.
        let createUser = P7Message(withName: "wired.account.create_user", spec: subscriber.spec)
        createUser.addParameter(field: "wired.account.name", value: createdUsername)
        createUser.addParameter(field: "wired.account.password", value: "integration-secret")
        XCTAssertTrue(subscriber.write(createUser))
        _ = try readMessage(from: subscriber, expectedName: "wired.okay", maxReads: 20)

        _ = try readMessage(from: subscriber, expectedName: "wired.account.accounts_changed", maxReads: 80, timeout: 1)
    }

    func testListGroupsPermissionDeniedForGuestAndAllowedForAdmin() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let guest = try runtime.connectClient(username: "guest", password: "")
        defer { guest.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: guest)
        _ = try sendLoginAndExpectSuccess(socket: guest, username: "guest", password: "")
        drainMessages(socket: guest)

        let listGroupsGuest = P7Message(withName: "wired.account.list_groups", spec: guest.spec)
        XCTAssertTrue(guest.write(listGroupsGuest))
        let denied = try readMessage(from: guest, expectedName: "wired.error", maxReads: 12)
        XCTAssertEqual(denied.string(forField: "wired.error.string"), "wired.error.permission_denied")

        let admin = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: admin)
        _ = try sendLoginAndExpectSuccess(socket: admin, username: "it_admin", password: "secret")
        drainMessages(socket: admin)

        let listGroupsAdmin = P7Message(withName: "wired.account.list_groups", spec: admin.spec)
        XCTAssertTrue(admin.write(listGroupsAdmin))
        _ = try readMessage(from: admin, expectedName: "wired.account.group_list.done", maxReads: 40)
    }

    func testAdminCreateReadEditAndDeleteGroupLifecycle() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let baseName = "integration_group_\(UUID().uuidString.prefix(8))"
        let renamed = "\(baseName)_renamed"

        let create = P7Message(withName: "wired.account.create_group", spec: socket.spec)
        create.addParameter(field: "wired.account.name", value: baseName)
        XCTAssertTrue(socket.write(create))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let readCreated = P7Message(withName: "wired.account.read_group", spec: socket.spec)
        readCreated.addParameter(field: "wired.account.name", value: baseName)
        XCTAssertTrue(socket.write(readCreated))
        let created = try readMessage(from: socket, expectedName: "wired.account.group", maxReads: 20)
        XCTAssertEqual(created.string(forField: "wired.account.name"), baseName)

        let edit = P7Message(withName: "wired.account.edit_group", spec: socket.spec)
        edit.addParameter(field: "wired.account.name", value: baseName)
        edit.addParameter(field: "wired.account.new_name", value: renamed)
        XCTAssertTrue(socket.write(edit))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let readOldName = P7Message(withName: "wired.account.read_group", spec: socket.spec)
        readOldName.addParameter(field: "wired.account.name", value: baseName)
        XCTAssertTrue(socket.write(readOldName))
        let missingOld = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(missingOld.string(forField: "wired.error.string"), "wired.error.account_not_found")

        let readRenamed = P7Message(withName: "wired.account.read_group", spec: socket.spec)
        readRenamed.addParameter(field: "wired.account.name", value: renamed)
        XCTAssertTrue(socket.write(readRenamed))
        let renamedGroup = try readMessage(from: socket, expectedName: "wired.account.group", maxReads: 20)
        XCTAssertEqual(renamedGroup.string(forField: "wired.account.name"), renamed)

        let delete = P7Message(withName: "wired.account.delete_group", spec: socket.spec)
        delete.addParameter(field: "wired.account.name", value: renamed)
        XCTAssertTrue(socket.write(delete))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let readDeleted = P7Message(withName: "wired.account.read_group", spec: socket.spec)
        readDeleted.addParameter(field: "wired.account.name", value: renamed)
        XCTAssertTrue(socket.write(readDeleted))
        let missingDeleted = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(missingDeleted.string(forField: "wired.error.string"), "wired.error.account_not_found")
    }

    func testBanlistGetBansReturnsInsertedEntryAndDone() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let pattern = "10.123.0.0/16"
        let add = P7Message(withName: "wired.banlist.add_ban", spec: socket.spec)
        add.addParameter(field: "wired.banlist.ip", value: pattern)
        XCTAssertTrue(socket.write(add))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let get = P7Message(withName: "wired.banlist.get_bans", spec: socket.spec)
        XCTAssertTrue(socket.write(get))

        var sawInsertedPattern = false
        for _ in 0..<40 {
            let message = try socket.readMessage(timeout: 3, enforceDeadline: true)
            if message.name == "wired.banlist.list",
               message.string(forField: "wired.banlist.ip") == pattern {
                sawInsertedPattern = true
            }
            if message.name == "wired.banlist.list.done" {
                break
            }
        }
        XCTAssertTrue(sawInsertedPattern)

        let delete = P7Message(withName: "wired.banlist.delete_ban", spec: socket.spec)
        delete.addParameter(field: "wired.banlist.ip", value: pattern)
        XCTAssertTrue(socket.write(delete))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)
    }

    func testEventFirstTimeAndDeleteEventsAreAccessibleForAdmin() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let firstTime = P7Message(withName: "wired.event.get_first_time", spec: socket.spec)
        XCTAssertTrue(socket.write(firstTime))
        let firstReply = try readMessage(from: socket, expectedName: "wired.event.first_time", maxReads: 20)
        XCTAssertNotNil(firstReply.date(forField: "wired.event.first_time"))

        let delete = P7Message(withName: "wired.event.delete_events", spec: socket.spec)
        delete.addParameter(field: "wired.event.from_time", value: Date(timeIntervalSince1970: 0))
        delete.addParameter(field: "wired.event.to_time", value: Date().addingTimeInterval(60))
        XCTAssertTrue(socket.write(delete))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)
    }

    func testDirectorySubscriberReceivesDirectoryChangedBroadcast() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let subscriber = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { subscriber.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: subscriber)
        _ = try sendLoginAndExpectSuccess(socket: subscriber, username: "it_admin", password: "secret")
        drainMessages(socket: subscriber)

        let actor = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { actor.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: actor)
        _ = try sendLoginAndExpectSuccess(socket: actor, username: "it_admin", password: "secret")
        drainMessages(socket: actor)

        let subscribeRoot = P7Message(withName: "wired.file.subscribe_directory", spec: subscriber.spec)
        subscribeRoot.addParameter(field: "wired.file.path", value: "/")
        XCTAssertTrue(subscriber.write(subscribeRoot))
        _ = try readMessage(from: subscriber, expectedName: "wired.okay", maxReads: 20)

        let createdPath = "/notify_\(UUID().uuidString.prefix(6))"
        let create = P7Message(withName: "wired.file.create_directory", spec: actor.spec)
        create.addParameter(field: "wired.file.path", value: createdPath)
        XCTAssertTrue(actor.write(create))
        _ = try readMessage(from: actor, expectedName: "wired.okay", maxReads: 20)

        let changed = try readMessage(from: subscriber, expectedName: "wired.file.directory_changed", maxReads: 40, timeout: 1)
        XCTAssertEqual(changed.string(forField: "wired.file.path"), "/")
    }
}

private func waitUntil(timeout: TimeInterval, interval: TimeInterval = 0.05, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return true
        }
        Thread.sleep(forTimeInterval: interval)
    }
    return condition()
}
