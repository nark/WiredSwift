import XCTest
import WiredSwift
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
}
