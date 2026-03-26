import XCTest
import WiredSwift
@testable import wired3Lib

final class BoardsControllerTests: XCTestCase {
    func testBoardCRUDAndPermissionFiltering() throws {
        let (controller, _) = try makeController()

        let added = controller.addBoard(
            path: "/staff",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: false,
            everyoneRead: false,
            everyoneWrite: false
        )
        XCTAssertNotNil(added)
        XCTAssertNil(
            controller.addBoard(
                path: "/staff",
                owner: "alice",
                group: "admins",
                ownerRead: true,
                ownerWrite: true,
                groupRead: true,
                groupWrite: false,
                everyoneRead: false,
                everyoneWrite: false
            )
        )

        XCTAssertEqual(controller.getBoards(forUser: "alice", group: "users").map(\.path), ["/staff"])
        XCTAssertEqual(controller.getBoards(forUser: "bob", group: "admins").map(\.path), ["/staff"])
        XCTAssertTrue(controller.getBoards(forUser: "bob", group: "users").isEmpty)

        XCTAssertTrue(
            controller.setBoardInfo(
                path: "/staff",
                owner: "alice",
                group: "admins",
                ownerRead: true,
                ownerWrite: true,
                groupRead: true,
                groupWrite: true,
                everyoneRead: true,
                everyoneWrite: false
            )
        )
        XCTAssertEqual(controller.getBoards(forUser: "bob", group: "users").map(\.path), ["/staff"])
    }

    func testRenameMoveBoardAndThreadLinkage() throws {
        let (controller, _) = try makeController()
        _ = controller.addBoard(
            path: "/boards/a",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )
        _ = controller.addBoard(
            path: "/boards/b",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )

        let thread = try XCTUnwrap(
            controller.addThread(
                board: "/boards/a",
                subject: "subject",
                text: "text",
                nick: "Alice",
                login: "alice"
            )
        )

        XCTAssertTrue(controller.renameBoard(path: "/boards/a", newPath: "/boards/a-renamed"))
        XCTAssertEqual(controller.getThread(uuid: thread.uuid)?.board, "/boards/a-renamed")
        XCTAssertEqual(controller.getThreads(forBoard: "/boards/a-renamed").count, 1)

        let moved = controller.moveThread(uuid: thread.uuid, toBoard: "/boards/b")
        XCTAssertEqual(moved?.board, "/boards/b")
        XCTAssertTrue(controller.getThreads(forBoard: "/boards/a-renamed").isEmpty)
        XCTAssertEqual(controller.getThreads(forBoard: "/boards/b").count, 1)
    }

    func testThreadAndPostLifecycle() throws {
        let (controller, _) = try makeController()
        _ = controller.addBoard(
            path: "/general",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )

        let thread = try XCTUnwrap(
            controller.addThread(
                board: "/general",
                subject: "Initial Subject",
                text: "Initial text",
                nick: "Alice",
                login: "alice"
            )
        )
        XCTAssertNotNil(controller.editThread(uuid: thread.uuid, subject: "Edited Subject", text: "Edited text"))

        let post = try XCTUnwrap(
            controller.addPost(
                threadUUID: thread.uuid,
                text: "First reply",
                nick: "Bob",
                login: "bob"
            )
        )
        XCTAssertEqual(controller.getPosts(forThread: thread.uuid).count, 1)
        XCTAssertEqual(controller.editPost(uuid: post.uuid, text: "Edited reply")?.text, "Edited reply")

        XCTAssertTrue(controller.deletePost(uuid: post.uuid))
        XCTAssertTrue(controller.getPosts(forThread: thread.uuid).isEmpty)

        XCTAssertTrue(controller.deleteThread(uuid: thread.uuid))
        XCTAssertNil(controller.getThread(uuid: thread.uuid))
    }

    func testDeleteBoardCascadesThreadsAndPosts() throws {
        let (controller, _) = try makeController()
        _ = controller.addBoard(
            path: "/cascade",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )
        let thread = try XCTUnwrap(
            controller.addThread(
                board: "/cascade",
                subject: "to delete",
                text: "thread text",
                nick: "Alice",
                login: "alice"
            )
        )
        let post = try XCTUnwrap(
            controller.addPost(
                threadUUID: thread.uuid,
                text: "reply",
                nick: "Bob",
                login: "bob"
            )
        )

        XCTAssertTrue(controller.deleteBoard(path: "/cascade"))
        XCTAssertNil(controller.getBoardInfo(path: "/cascade"))
        XCTAssertNil(controller.getThread(uuid: thread.uuid))
        XCTAssertFalse(controller.posts.keys.contains(post.uuid))
    }

    func testSearchFindsThreadAndPostAcrossScopedBoards() throws {
        let (controller, _) = try makeController()
        _ = controller.addBoard(
            path: "/engineering",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )
        _ = controller.addBoard(
            path: "/private",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )

        let thread = try XCTUnwrap(
            controller.addThread(
                board: "/engineering",
                subject: "Wired release plan",
                text: "Milestone alpha",
                nick: "Alice",
                login: "alice"
            )
        )
        let post = try XCTUnwrap(
            controller.addPost(
                threadUUID: thread.uuid,
                text: "Release checklist ready",
                nick: "Bob",
                login: "bob"
            )
        )

        _ = controller.addThread(
            board: "/private",
            subject: "Other topic",
            text: "Nothing about release",
            nick: "Eve",
            login: "eve"
        )

        let results = try controller.search(query: "release", boardPaths: ["/engineering"], limit: 10)
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.boardPath == "/engineering" })
        XCTAssertTrue(results.contains { $0.threadUUID == thread.uuid && $0.postUUID == nil })
        XCTAssertTrue(results.contains { $0.postUUID == post.uuid })
    }

    func testThreadAndPostReactionsToggleAndSummaries() throws {
        let (controller, _) = try makeController()
        _ = controller.addBoard(
            path: "/react",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )
        let thread = try XCTUnwrap(
            controller.addThread(
                board: "/react",
                subject: "Reactions",
                text: "Thread text",
                nick: "Alice",
                login: "alice"
            )
        )
        let post = try XCTUnwrap(
            controller.addPost(
                threadUUID: thread.uuid,
                text: "Reply",
                nick: "Bob",
                login: "bob"
            )
        )

        let addThread = try XCTUnwrap(
            controller.toggleReaction(
                threadUUID: thread.uuid,
                postUUID: nil,
                emoji: "👍",
                login: "alice",
                nick: "Alice"
            )
        )
        XCTAssertTrue(addThread.added)
        XCTAssertEqual(addThread.count, 1)
        XCTAssertEqual(controller.getThreadReactionEmojis(threadUUID: thread.uuid), "👍")

        let replaceThread = try XCTUnwrap(
            controller.toggleReaction(
                threadUUID: thread.uuid,
                postUUID: nil,
                emoji: "🔥",
                login: "alice",
                nick: "Alice"
            )
        )
        XCTAssertTrue(replaceThread.added)
        XCTAssertEqual(replaceThread.replacedEmoji, "👍")
        XCTAssertEqual(controller.getThreadReactionEmojis(threadUUID: thread.uuid), "🔥")

        let addPost = try XCTUnwrap(
            controller.toggleReaction(
                threadUUID: thread.uuid,
                postUUID: post.uuid,
                emoji: "🎉",
                login: "bob",
                nick: "Bob"
            )
        )
        XCTAssertTrue(addPost.added)
        let postReactions = controller.getReactions(threadUUID: thread.uuid, postUUID: post.uuid, currentLogin: "bob")
        XCTAssertEqual(postReactions.count, 1)
        XCTAssertEqual(postReactions.first?.emoji, "🎉")
        XCTAssertEqual(postReactions.first?.count, 1)
        XCTAssertEqual(postReactions.first?.isOwn, true)
    }

    func testReactionsAreRemovedWhenPostOrThreadIsDeleted() throws {
        let (controller, _) = try makeController()
        _ = controller.addBoard(
            path: "/cleanup",
            owner: "alice",
            group: "admins",
            ownerRead: true,
            ownerWrite: true,
            groupRead: true,
            groupWrite: true,
            everyoneRead: true,
            everyoneWrite: false
        )
        let thread = try XCTUnwrap(
            controller.addThread(
                board: "/cleanup",
                subject: "Cleanup",
                text: "Thread text",
                nick: "Alice",
                login: "alice"
            )
        )
        let post = try XCTUnwrap(
            controller.addPost(
                threadUUID: thread.uuid,
                text: "Reply",
                nick: "Bob",
                login: "bob"
            )
        )

        _ = controller.toggleReaction(threadUUID: thread.uuid, postUUID: nil, emoji: "👍", login: "alice", nick: "Alice")
        _ = controller.toggleReaction(threadUUID: thread.uuid, postUUID: post.uuid, emoji: "🎯", login: "bob", nick: "Bob")

        XCTAssertTrue(controller.deletePost(uuid: post.uuid))
        XCTAssertTrue(controller.getReactions(threadUUID: thread.uuid, postUUID: post.uuid, currentLogin: "bob").isEmpty)

        XCTAssertTrue(controller.deleteThread(uuid: thread.uuid))
        XCTAssertTrue(controller.getReactions(threadUUID: thread.uuid, postUUID: nil, currentLogin: "alice").isEmpty)
    }

    func testPersistenceRoundTripReloadsBoardsThreadsAndPosts() throws {
        let (_, dbPath) = try makeController()

        do {
            let writer = BoardsController(databasePath: dbPath)
            _ = writer.addBoard(
                path: "/persist",
                owner: "alice",
                group: "admins",
                ownerRead: true,
                ownerWrite: true,
                groupRead: true,
                groupWrite: true,
                everyoneRead: true,
                everyoneWrite: false
            )
            let thread = try XCTUnwrap(
                writer.addThread(
                    board: "/persist",
                    subject: "Persisted subject",
                    text: "Persisted text",
                    nick: "Alice",
                    login: "alice"
                )
            )
            _ = writer.addPost(threadUUID: thread.uuid, text: "Persisted reply", nick: "Bob", login: "bob")
        }

        let reader = BoardsController(databasePath: dbPath)
        XCTAssertEqual(reader.getBoards(forUser: "alice", group: "admins").count, 1)
        let threads = reader.getThreads(forBoard: "/persist")
        XCTAssertEqual(threads.count, 1)
        XCTAssertEqual(threads.first?.subject, "Persisted subject")
        XCTAssertEqual(threads.first?.posts.count, 1)
        XCTAssertEqual(threads.first?.posts.first?.text, "Persisted reply")
    }

    private func makeController() throws -> (BoardsController, String) {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }
        let dbPath = tempDir.appendingPathComponent("boards.sqlite").path
        return (BoardsController(databasePath: dbPath), dbPath)
    }
}
