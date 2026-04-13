import XCTest
import WiredSwift
@testable import wired3Lib

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
            waitUntil(timeout: 6) {
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
            waitUntil(timeout: 6) {
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
            waitUntil(timeout: 6) {
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
        var sawCreationTime = false
        var sawModificationTime = false
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
                sawCreationTime = message.date(forField: "wired.file.creation_time") != nil
                sawModificationTime = message.date(forField: "wired.file.modification_time") != nil
            }
            if message.name == "wired.file.file_list.done" {
                break
            }
        }
        XCTAssertTrue(sawDir)
        XCTAssertTrue(sawCreationTime)
        XCTAssertTrue(sawModificationTime)

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

    func testMonitorGetUsersListsLoggedInUsersAndChecksPermissions() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.ensurePrivilegedUser(username: "it_admin_2", password: "secret2")
        defer { try? runtime.stop() }

        let guest = try runtime.connectClient(username: "guest", password: "")
        defer { guest.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: guest)
        _ = try sendLoginAndExpectSuccess(socket: guest, username: "guest", password: "")
        drainMessages(socket: guest)

        let deniedRequest = P7Message(withName: "wired.user.get_users", spec: guest.spec)
        XCTAssertTrue(guest.write(deniedRequest))
        let denied = try readMessage(from: guest, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(denied.string(forField: "wired.error.string"), "wired.error.permission_denied")

        let admin = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { admin.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: admin)
        let adminLogin = try sendLoginAndExpectSuccess(socket: admin, username: "it_admin", password: "secret")
        let adminUserID = try XCTUnwrap(adminLogin.uint32(forField: "wired.user.id"))
        drainMessages(socket: admin)

        let peer = try runtime.connectClient(username: "it_admin_2", password: "secret2")
        defer { peer.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: peer)
        let peerLogin = try sendLoginAndExpectSuccess(socket: peer, username: "it_admin_2", password: "secret2")
        let peerUserID = try XCTUnwrap(peerLogin.uint32(forField: "wired.user.id"))
        drainMessages(socket: peer)

        let setStatus = P7Message(withName: "wired.user.set_status", spec: peer.spec)
        setStatus.addParameter(field: "wired.user.status", value: "Monitoring me")
        XCTAssertTrue(peer.write(setStatus))
        _ = try readMessage(from: peer, expectedName: "wired.okay", maxReads: 20)

        let request = P7Message(withName: "wired.user.get_users", spec: admin.spec)
        XCTAssertTrue(admin.write(request))

        var listedUserIDs = Set<UInt32>()
        var peerStatus: String?
        var sawIdleTime = false
        var sawState = false

        for _ in 0..<80 {
            let message: P7Message
            do {
                message = try admin.readMessage(timeout: 1, enforceDeadline: true)
            } catch {
                continue
            }

            if message.name == "wired.user.user_list" {
                if let userID = message.uint32(forField: "wired.user.id") {
                    listedUserIDs.insert(userID)
                    if userID == peerUserID {
                        peerStatus = message.string(forField: "wired.user.status")
                    }
                }

                if message.date(forField: "wired.user.idle_time") != nil {
                    sawIdleTime = true
                }

                if message.uint32(forField: "wired.user.state") != nil
                    || message.enumeration(forField: "wired.user.state") != nil {
                    sawState = true
                }
            }

            if message.name == "wired.user.user_list.done" {
                break
            }
        }

        XCTAssertTrue(listedUserIDs.contains(adminUserID))
        XCTAssertTrue(listedUserIDs.contains(peerUserID))
        XCTAssertEqual(peerStatus, "Monitoring me")
        XCTAssertTrue(sawIdleTime)
        XCTAssertTrue(sawState)
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

    func testTrackerGetCategoriesReturnsTrackerNotEnabledWhenDisabled() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: false, categories: ["Chat", "Movies"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let get = P7Message(withName: "wired.tracker.get_categories", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let error = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(error.string(forField: "wired.error.string"), "wired.error.tracker_not_enabled")
    }

    func testTrackerGetCategoriesDeniedForGuestWithoutTrackerPrivilege() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.configureTracker(enabled: true, categories: ["Chat", "Movies"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "guest", password: "")
        drainMessages(socket: socket)

        let get = P7Message(withName: "wired.tracker.get_categories", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let error = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(error.string(forField: "wired.error.string"), "wired.error.permission_denied")
    }

    func testTrackerGetCategoriesReturnsConfiguredCategoriesForPrivilegedUser() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat", "Regional/Europe"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let get = P7Message(withName: "wired.tracker.get_categories", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let response = try readMessage(from: socket, expectedName: "wired.tracker.categories", maxReads: 20)
        XCTAssertEqual(response.stringList(forField: "wired.tracker.categories"), ["Chat", "Regional/Europe"])
    }

    func testTrackerGetServersReturnsOnlyDoneWhenNoServersRegistered() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let get = P7Message(withName: "wired.tracker.get_servers", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let done = try readMessage(from: socket, expectedName: "wired.tracker.server_list.done", maxReads: 20)
        XCTAssertEqual(done.name, "wired.tracker.server_list.done")
    }

    func testTrackerSendRegisterDeniedForGuestWithoutTrackerPrivilege() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.configureTracker(enabled: true, categories: ["Chat"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "guest", password: "")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "guest", password: "")
        drainMessages(socket: socket)

        let register = trackerRegisterMessage(
            spec: socket.spec,
            category: "Chat",
            name: "Guest Tracker Server",
            description: "guest cannot register"
        )
        XCTAssertTrue(socket.write(register))
        let error = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(error.string(forField: "wired.error.string"), "wired.error.permission_denied")
    }

    func testTrackerRegisterThenListReturnsRegisteredServer() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat", "Movies"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let register = trackerRegisterMessage(
            spec: socket.spec,
            category: "Chat",
            name: "Integration Tracker Server",
            description: "registered from integration test",
            users: 12,
            filesCount: 34,
            filesSize: 56,
            port: UInt32(runtime.port)
        )
        XCTAssertTrue(socket.write(register))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let get = P7Message(withName: "wired.tracker.get_servers", spec: socket.spec)
        XCTAssertTrue(socket.write(get))

        let listed = try readMessage(from: socket, expectedName: "wired.tracker.server_list", maxReads: 20)
        XCTAssertEqual(listed.string(forField: "wired.info.name"), "Integration Tracker Server")
        XCTAssertEqual(listed.string(forField: "wired.info.description"), "registered from integration test")
        XCTAssertEqual(listed.string(forField: "wired.tracker.category"), "Chat")
        XCTAssertEqual(listed.bool(forField: "wired.tracker.tracker"), true)
        XCTAssertEqual(listed.uint32(forField: "wired.tracker.users"), 12)
        XCTAssertEqual(listed.uint64(forField: "wired.info.files.count"), 34)
        XCTAssertEqual(listed.uint64(forField: "wired.info.files.size"), 56)

        let url = try XCTUnwrap(listed.string(forField: "wired.tracker.url"))
        XCTAssertTrue(url.contains("127.0.0.1"))
        XCTAssertTrue(url.hasSuffix("/Chat"))

        _ = try readMessage(from: socket, expectedName: "wired.tracker.server_list.done", maxReads: 20)
    }

    func testTrackerSendUpdateUpdatesRegisteredServerStats() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let register = trackerRegisterMessage(
            spec: socket.spec,
            category: "Chat",
            name: "Update Test Server",
            description: "before update",
            users: 1,
            filesCount: 2,
            filesSize: 3
        )
        XCTAssertTrue(socket.write(register))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let update = trackerUpdateMessage(spec: socket.spec, users: 99, filesCount: 1234, filesSize: 5678)
        XCTAssertTrue(socket.write(update))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let get = P7Message(withName: "wired.tracker.get_servers", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let listed = try readMessage(from: socket, expectedName: "wired.tracker.server_list", maxReads: 20)
        XCTAssertEqual(listed.uint32(forField: "wired.tracker.users"), 99)
        XCTAssertEqual(listed.uint64(forField: "wired.info.files.count"), 1234)
        XCTAssertEqual(listed.uint64(forField: "wired.info.files.size"), 5678)
        _ = try readMessage(from: socket, expectedName: "wired.tracker.server_list.done", maxReads: 20)
    }

    func testTrackerSendUpdateReturnsNotRegisteredWithoutPriorRegister() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let update = trackerUpdateMessage(spec: socket.spec, users: 7, filesCount: 8, filesSize: 9)
        XCTAssertTrue(socket.write(update))
        let error = try readMessage(from: socket, expectedName: "wired.error", maxReads: 20)
        XCTAssertEqual(error.string(forField: "wired.error.string"), "wired.error.not_registered")
    }

    func testTrackerRegisterNormalizesUnknownCategoryToEmptyString() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let register = trackerRegisterMessage(
            spec: socket.spec,
            category: "Software",
            name: "Unknown Category Server",
            description: "category should be normalized"
        )
        XCTAssertTrue(socket.write(register))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let get = P7Message(withName: "wired.tracker.get_servers", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let listed = try readMessage(from: socket, expectedName: "wired.tracker.server_list", maxReads: 20)
        XCTAssertEqual(listed.string(forField: "wired.tracker.category"), "")
        let url = try XCTUnwrap(listed.string(forField: "wired.tracker.url"))
        XCTAssertTrue(url.hasSuffix("/"))
        _ = try readMessage(from: socket, expectedName: "wired.tracker.server_list.done", maxReads: 20)
    }

    func testTrackerRegisterReplacesExistingServerForSameSourceIP() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat", "Movies"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let first = trackerRegisterMessage(
            spec: socket.spec,
            category: "Chat",
            name: "First Server",
            description: "first"
        )
        XCTAssertTrue(socket.write(first))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let second = trackerRegisterMessage(
            spec: socket.spec,
            category: "Movies",
            name: "Second Server",
            description: "second",
            users: 88,
            filesCount: 99,
            filesSize: 111,
            port: 9999
        )
        XCTAssertTrue(socket.write(second))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        let get = P7Message(withName: "wired.tracker.get_servers", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let listed = try readMessage(from: socket, expectedName: "wired.tracker.server_list", maxReads: 20)
        XCTAssertEqual(listed.string(forField: "wired.info.name"), "Second Server")
        XCTAssertEqual(listed.string(forField: "wired.tracker.category"), "Movies")
        XCTAssertEqual(listed.uint32(forField: "wired.tracker.users"), 88)
        let url = try XCTUnwrap(listed.string(forField: "wired.tracker.url"))
        XCTAssertTrue(url.contains(":9999/Movies"))
        _ = try readMessage(from: socket, expectedName: "wired.tracker.server_list.done", maxReads: 20)

        do {
            let unexpected = try socket.readMessage(timeout: 0.3, enforceDeadline: true)
            XCTFail("Expected no extra tracker server_list messages, got \(unexpected.name ?? "unknown")")
        } catch {
            // No extra messages is the expected outcome.
        }
    }

    func testTrackerGetServersOmitsExpiredEntries() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        runtime.configureTracker(enabled: true, categories: ["Chat"])
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let register = trackerRegisterMessage(
            spec: socket.spec,
            category: "Chat",
            name: "Ephemeral Server",
            description: "should expire"
        )
        XCTAssertTrue(socket.write(register))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 20)

        runtime.expireTrackedServersForTesting()

        let get = P7Message(withName: "wired.tracker.get_servers", spec: socket.spec)
        XCTAssertTrue(socket.write(get))
        let done = try readMessage(from: socket, expectedName: "wired.tracker.server_list.done", maxReads: 20)
        XCTAssertEqual(done.name, "wired.tracker.server_list.done")
    }

    private func trackerRegisterMessage(
        spec: P7Spec,
        category: String,
        name: String,
        description: String,
        users: UInt32 = 5,
        filesCount: UInt64 = 10,
        filesSize: UInt64 = 20,
        port: UInt32 = 4871
    ) -> P7Message {
        let register = P7Message(withName: "wired.tracker.send_register", spec: spec)
        register.addParameter(field: "wired.tracker.tracker", value: true)
        register.addParameter(field: "wired.tracker.category", value: category)
        register.addParameter(field: "wired.tracker.port", value: port)
        register.addParameter(field: "wired.tracker.users", value: users)
        register.addParameter(field: "wired.info.name", value: name)
        register.addParameter(field: "wired.info.description", value: description)
        register.addParameter(field: "wired.info.files.count", value: filesCount)
        register.addParameter(field: "wired.info.files.size", value: filesSize)
        return register
    }

    private func trackerUpdateMessage(spec: P7Spec, users: UInt32, filesCount: UInt64, filesSize: UInt64) -> P7Message {
        let update = P7Message(withName: "wired.tracker.send_update", spec: spec)
        update.addParameter(field: "wired.tracker.users", value: users)
        update.addParameter(field: "wired.info.files.count", value: filesCount)
        update.addParameter(field: "wired.info.files.size", value: filesSize)
        return update
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

    func testExternalFilesystemChangeTriggersDirectoryNotificationAndSearchIndexRefresh() throws {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "it_admin", password: "secret")
        defer { try? runtime.stop() }

        let socket = try runtime.connectClient(username: "it_admin", password: "secret")
        defer { socket.disconnect() }
        try sendClientInfoAndExpectServerInfo(socket: socket)
        _ = try sendLoginAndExpectSuccess(socket: socket, username: "it_admin", password: "secret")
        drainMessages(socket: socket)

        let subscribe = P7Message(withName: "wired.file.subscribe_directory", spec: socket.spec)
        subscribe.addParameter(field: "wired.file.path", value: "/")
        XCTAssertTrue(socket.write(subscribe))
        _ = try readMessage(from: socket, expectedName: "wired.okay", maxReads: 12)

        let externalFile = runtime.filesURL.appendingPathComponent("outside.txt")
        try Data("external".utf8).write(to: externalFile)

        let changed = try readMessage(from: socket, expectedName: "wired.file.directory_changed", maxReads: 80, timeout: 5)
        XCTAssertEqual(changed.string(forField: "wired.file.path"), "/")

        XCTAssertTrue(waitUntil(timeout: 5, interval: 0.1) {
            runtime.indexedFilesCount() == 1
        })
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
        let first = try readMessage(
            from: subscriber,
            expectedNames: ["wired.okay", "wired.account.accounts_changed"],
            maxReads: 80,
            timeout: 1
        )

        // Depending on scheduler timing, the broadcast may arrive before or
        // after the command acknowledgement. Validate that both are observed.
        if first.name == "wired.okay" {
            _ = try readMessage(from: subscriber, expectedName: "wired.account.accounts_changed", maxReads: 80, timeout: 1)
        } else {
            _ = try readMessage(from: subscriber, expectedName: "wired.okay", maxReads: 40, timeout: 1)
        }
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
