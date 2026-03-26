import Foundation
import XCTest
import WiredSwift
@testable import wired3Lib

final class DomainModelTests: XCTestCase {
    func testBoardNameAndPermissionsForOwnerGroupAndEveryone() {
        let board = Board(
            path: "/staff/announcements",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: false,
            everyoneRead: false,
            everyoneWrite: false
        )

        XCTAssertEqual(board.name, "announcements")
        XCTAssertTrue(board.canRead(user: "alice", group: "other"))
        XCTAssertTrue(board.canRead(user: "bob", group: "admins"))
        XCTAssertFalse(board.canRead(user: "bob", group: "users"))
        XCTAssertTrue(board.canWrite(user: "alice", group: "admins"))
        XCTAssertFalse(board.canWrite(user: "bob", group: "admins"))

        board.everyoneWrite = true
        XCTAssertTrue(board.canWrite(user: "someone", group: "users"))
    }

    func testThreadReplyDerivedPropertiesTrackLatestPost() {
        let thread = Thread(
            uuid: "thread-1",
            board: "/board",
            subject: "subject",
            text: "body",
            nick: "nick",
            login: "login",
            postDate: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(thread.replies, 0)
        XCTAssertNil(thread.latestReply)
        XCTAssertNil(thread.latestReplyDate)
        XCTAssertNil(thread.latestReplyUUID)

        let post1 = Post(
            uuid: "post-1",
            thread: thread.uuid,
            text: "first",
            nick: "n1",
            login: "l1",
            postDate: Date(timeIntervalSince1970: 20)
        )
        let post2 = Post(
            uuid: "post-2",
            thread: thread.uuid,
            text: "second",
            nick: "n2",
            login: "l2",
            postDate: Date(timeIntervalSince1970: 30)
        )

        thread.posts = [post1, post2]
        XCTAssertEqual(thread.replies, 2)
        XCTAssertEqual(thread.latestReply?.uuid, "post-2")
        XCTAssertEqual(thread.latestReplyDate, Date(timeIntervalSince1970: 30))
        XCTAssertEqual(thread.latestReplyUUID, "post-2")
    }

    func testTransferInitialStateAndIdentityEquality() {
        let client = makeClient(userID: 99)
        let message = P7Message(withName: "wired.transfer.upload_file", spec: client.socket.spec)

        let upload = Transfer(path: "/upload.bin", client: client, message: message, type: .upload)
        let download = Transfer(path: "/download.bin", client: client, message: message, type: .download)

        XCTAssertEqual(upload.path, "/upload.bin")
        XCTAssertEqual(upload.type, .upload)
        XCTAssertEqual(upload.state, .queued)
        XCTAssertEqual(download.type, .download)
        XCTAssertTrue(upload == upload)
        XCTAssertFalse(upload == download)
    }

    func testUserHasGroupParsesCommaSeparatedGroups() {
        let user = User(username: "alice", password: "hashed")
        user.group = "admin"
        user.groups = "staff,  qa ,ops"

        XCTAssertTrue(user.hasGroup(string: "admin"))
        XCTAssertTrue(user.hasGroup(string: "qa"))
        XCTAssertTrue(user.hasGroup(string: "ops"))
        XCTAssertFalse(user.hasGroup(string: "unknown"))
    }

    func testUserDropboxPermissionsOwnerAndGroupChecks() {
        let user = User(username: "alice", password: "hashed")
        user.group = "engineering"
        user.groups = "engineering,qa"

        var mode: File.FilePermissions = []
        mode.insert(.ownerRead)
        mode.insert(.ownerWrite)
        mode.insert(.groupRead)
        let privilege = FilePrivilege(owner: "alice", group: "engineering", mode: mode)

        XCTAssertTrue(user.hasPermission(toRead: privilege))
        XCTAssertTrue(user.hasPermission(toWrite: privilege))

        let other = User(username: "bob", password: "hashed")
        other.group = "engineering"
        other.groups = "engineering"
        XCTAssertTrue(other.hasPermission(toRead: privilege))
        XCTAssertFalse(other.hasPermission(toWrite: privilege))
    }

    func testUserAccessAllDropboxesPrivilegeOverridesFileMode() {
        let user = User(username: "alice", password: "hashed")
        user.privileges = [UserPrivilege(name: "wired.account.file.access_all_dropboxes", value: true, userId: 1)]

        let privilege = FilePrivilege(owner: "owner", group: "group", mode: [])
        XCTAssertTrue(user.hasPermission(toRead: privilege))
        XCTAssertTrue(user.hasPermission(toWrite: privilege))
    }
}
