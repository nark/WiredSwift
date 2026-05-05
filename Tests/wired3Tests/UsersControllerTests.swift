import XCTest
import WiredSwift
import GRDB
@testable import wired3Lib

final class UsersControllerTests: XCTestCase {
    func testNextUserIDIncrementsSequentially() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        XCTAssertEqual(usersController.nextUserID(), 1)
        XCTAssertEqual(usersController.nextUserID(), 2)
        XCTAssertEqual(usersController.nextUserID(), 3)
    }

    func testUserLookupByPasswordSetsSaltOnFirstSuccessfulLogin() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "secret".sha256())
        XCTAssertTrue(usersController.save(user: user))

        let authenticated = usersController.user(withUsername: "alice", password: "secret".sha256())
        XCTAssertNotNil(authenticated)
        XCTAssertNotNil(authenticated?.passwordSalt)
        XCTAssertFalse(authenticated?.passwordSalt?.isEmpty ?? true)
    }

    func testUsersMatchingIdentityQueryHonorsLimit() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let first = User(username: "anna", password: "x")
        first.fullName = "Anna Admin"
        first.identity = "anna-id"
        XCTAssertTrue(usersController.save(user: first))

        let second = User(username: "anne", password: "x")
        second.fullName = "Anne Operator"
        second.identity = "anne-id"
        XCTAssertTrue(usersController.save(user: second))

        let results = usersController.users(matchingIdentityQuery: "ann", limit: 1)
        XCTAssertEqual(results.count, 1)
    }

    func testUsersMatchingIdentityQueryBlankReturnsEmptyArray() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "anna", password: "x")
        user.identity = "id-anna"
        XCTAssertTrue(usersController.save(user: user))

        XCTAssertEqual(usersController.users(matchingIdentityQuery: "   ").count, 0)
    }

    func testPasswordAccessorsReturnStoredPasswordAndSalt() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "secret-hash")
        user.passwordSalt = "salt-abc"
        XCTAssertTrue(usersController.save(user: user))

        XCTAssertEqual(usersController.passwordForUsername(username: "alice"), "secret-hash")
        XCTAssertEqual(usersController.passwordSaltForUsername(username: "alice"), "salt-abc")
        XCTAssertNil(usersController.passwordForUsername(username: "nobody"))
        XCTAssertNil(usersController.passwordSaltForUsername(username: "nobody"))
    }

    func testUserLookupByPasswordReturnsNilWhenPasswordIsWrong() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "secret".sha256())
        XCTAssertTrue(usersController.save(user: user))

        XCTAssertNil(usersController.user(withUsername: "alice", password: "wrong".sha256()))
    }

    func testUserLookupByPasswordKeepsExistingSaltUntouched() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "secret".sha256())
        user.passwordSalt = "already-set-salt"
        XCTAssertTrue(usersController.save(user: user))

        let authenticated = usersController.user(withUsername: "alice", password: "secret".sha256())
        XCTAssertEqual(authenticated?.passwordSalt, "already-set-salt")
    }

    func testIsIdentityAvailableReflectsExistingRows() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "x")
        user.identity = "identity-alice"
        XCTAssertTrue(usersController.save(user: user))

        XCTAssertFalse(usersController.isIdentityAvailable("identity-alice"))
        XCTAssertTrue(usersController.isIdentityAvailable("identity-bob"))
    }

    func testUsersReturnsSavedUsers() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        XCTAssertTrue(usersController.save(user: User(username: "alice", password: "x")))
        XCTAssertTrue(usersController.save(user: User(username: "bob", password: "y")))

        let usernames = Set(usersController.users().compactMap(\.username))
        XCTAssertEqual(usernames, Set(["alice", "bob"]))
    }

    func testSetUserPrivilegeInsertThenUpdate() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "x")
        XCTAssertTrue(usersController.save(user: user))
        let persisted = try XCTUnwrap(usersController.user(withUsername: "alice"))

        XCTAssertTrue(usersController.setUserPrivilege("wired.account.chat.create_chats", value: true, for: persisted))
        XCTAssertTrue(usersController.setUserPrivilege("wired.account.chat.create_chats", value: false, for: persisted))

        let withPrivileges = try XCTUnwrap(usersController.userWithPrivileges(withUsername: "alice"))
        let privilege = withPrivileges.privileges.first(where: { $0.name == "wired.account.chat.create_chats" })
        XCTAssertEqual(privilege?.value, false)
    }

    func testSetUserPrivilegeWithoutPersistedUserReturnsFalse() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let transient = User(username: "transient", password: "x")
        XCTAssertFalse(usersController.setUserPrivilege("wired.account.chat.create_chats", value: true, for: transient))
    }

    func testUserWithPrivilegesCanLoadByIdentity() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "x")
        user.identity = "identity-alice"
        XCTAssertTrue(usersController.save(user: user))
        let persisted = try XCTUnwrap(usersController.user(withUsername: "alice"))
        XCTAssertTrue(usersController.setUserPrivilege("wired.account.events.view_events", value: true, for: persisted))

        let byIdentity = try XCTUnwrap(usersController.userWithPrivileges(identity: "identity-alice"))
        XCTAssertEqual(byIdentity.username, "alice")
        XCTAssertEqual(byIdentity.privileges.first(where: { $0.name == "wired.account.events.view_events" })?.value, true)
        XCTAssertNil(usersController.userWithPrivileges(identity: "identity-unknown"))
    }

    func testDeleteUserRemovesUserAndPrivileges() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "x")
        XCTAssertTrue(usersController.save(user: user))
        let persisted = try XCTUnwrap(usersController.user(withUsername: "alice"))
        XCTAssertTrue(usersController.setUserPrivilege("wired.account.chat.create_chats", value: true, for: persisted))

        XCTAssertTrue(usersController.delete(user: persisted))
        XCTAssertNil(usersController.user(withUsername: "alice"))

        let orphanCount = try usersController.databaseController.dbQueue.read { db in
            try UserPrivilege.filter(Column("user_id") == persisted.id!).fetchCount(db)
        }
        XCTAssertEqual(orphanCount, 0)
    }

    func testDeleteUserWithoutIDReturnsFalse() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let transient = User(username: "noid", password: "x")
        XCTAssertFalse(usersController.delete(user: transient))
    }

    func testSaveGroupFetchGroupsAndSetGroupPrivilege() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let group = Group(name: "ops")
        group.color = "3"
        XCTAssertTrue(usersController.save(group: group))

        let fetched = try XCTUnwrap(usersController.group(withName: "ops"))
        XCTAssertEqual(fetched.color, "3")
        XCTAssertTrue(usersController.setGroupPrivilege("wired.account.file.list_files", value: true, for: fetched))
        XCTAssertTrue(usersController.setGroupPrivilege("wired.account.file.list_files", value: false, for: fetched))

        let withPrivileges = try XCTUnwrap(usersController.groupWithPrivileges(withName: "ops"))
        XCTAssertEqual(withPrivileges.privileges.first(where: { $0.name == "wired.account.file.list_files" })?.value, false)
        XCTAssertNotNil(usersController.groups().first(where: { $0.name == "ops" }))
    }

    func testSetGroupPrivilegeWithoutPersistedGroupReturnsFalse() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let transient = Group(name: "transient")
        XCTAssertFalse(usersController.setGroupPrivilege("wired.account.file.list_files", value: true, for: transient))
    }

    func testDeleteGroupRemovesGroupAndPrivileges() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let group = Group(name: "ops")
        XCTAssertTrue(usersController.save(group: group))
        let persisted = try XCTUnwrap(usersController.group(withName: "ops"))
        XCTAssertTrue(usersController.setGroupPrivilege("wired.account.file.list_files", value: true, for: persisted))

        XCTAssertTrue(usersController.delete(group: persisted))
        XCTAssertNil(usersController.group(withName: "ops"))

        let orphanCount = try usersController.databaseController.dbQueue.read { db in
            try GroupPrivilege.filter(Column("group_id") == persisted.id!).fetchCount(db)
        }
        XCTAssertEqual(orphanCount, 0)
    }

    func testDeleteGroupWithoutIDReturnsFalse() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let transient = Group(name: "noid")
        XCTAssertFalse(usersController.delete(group: transient))
    }

    func testLegacyPrivilegeMigrationBackfillsFileMetadataPrivilegesFromSetType() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let usersController = UsersController(databaseController: makeDatabaseController(tempDir: tempDir))

        let user = User(username: "alice", password: "x")
        XCTAssertTrue(usersController.save(user: user))
        let persistedUser = try XCTUnwrap(usersController.user(withUsername: "alice"))
        XCTAssertTrue(usersController.setUserPrivilege("wired.account.file.set_type", value: true, for: persistedUser))

        let group = Group(name: "ops")
        XCTAssertTrue(usersController.save(group: group))
        let persistedGroup = try XCTUnwrap(usersController.group(withName: "ops"))
        XCTAssertTrue(usersController.setGroupPrivilege("wired.account.file.set_type", value: true, for: persistedGroup))

        usersController.migrateLegacyPrivilegesSchemaIfNeeded()

        let migratedUser = try XCTUnwrap(usersController.userWithPrivileges(withUsername: "alice"))
        XCTAssertEqual(migratedUser.privileges.first(where: { $0.name == "wired.account.file.set_comment" })?.value, true)
        XCTAssertEqual(migratedUser.privileges.first(where: { $0.name == "wired.account.file.set_label" })?.value, true)

        let migratedGroup = try XCTUnwrap(usersController.groupWithPrivileges(withName: "ops"))
        XCTAssertEqual(migratedGroup.privileges.first(where: { $0.name == "wired.account.file.set_comment" })?.value, true)
        XCTAssertEqual(migratedGroup.privileges.first(where: { $0.name == "wired.account.file.set_label" })?.value, true)
    }
}
