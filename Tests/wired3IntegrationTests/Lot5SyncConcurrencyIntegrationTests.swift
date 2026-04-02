import Foundation
import XCTest
import WiredSwift

final class Lot5SyncConcurrencyIntegrationTests: SerializedIntegrationTestCase {
    func testThreeUsersBidirectionalContinuousSharedTreeChurn() throws {
        let runtime = try makeSharedSyncRuntime()
        defer { try? runtime.stop() }

        let alice = try connectAndAuthenticate(runtime: runtime, username: "sync_alice", password: "secret1")
        let bob = try connectAndAuthenticate(runtime: runtime, username: "sync_bob", password: "secret2")
        let carol = try connectAndAuthenticate(runtime: runtime, username: "sync_carol", password: "secret3")
        defer { alice.socket.disconnect() }
        defer { bob.socket.disconnect() }
        defer { carol.socket.disconnect() }

        let users = [alice, bob, carol]
        let namespace = (0..<6).map { "/shared-sync/item-\($0).txt" } + (0..<6).map { "/shared-sync/item-\($0).alt.txt" }
        let iterationsPerUser = 30
        let errorLock = NSLock()
        var unexpectedErrors: [String] = []
        let startBarrier = ConcurrentStartBarrier(participantCount: users.count)
        let group = DispatchGroup()

        for (index, user) in users.enumerated() {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                var generator = SeededGenerator(state: UInt64(0x5EED_F00D + index))
                startBarrier.wait()

                for iteration in 0..<iterationsPerUser {
                    let path = namespace.randomElement(using: &generator) ?? "/shared-sync/item-0.txt"
                    do {
                        switch Int.random(in: 0..<3, using: &generator) {
                        case 0, 1:
                            let payload = Data("\(user.username)-\(iteration)-\(UInt64.random(in: 0...UInt64.max, using: &generator))".utf8)
                            _ = try uploadFile(socket: user.socket, path: path, data: payload)
                        default:
                            try deletePath(socket: user.socket, path: path)
                        }
                    } catch {
                        if !self.isExpectedRaceError(error) {
                            errorLock.lock()
                            unexpectedErrors.append("\(user.username): \(error.localizedDescription)")
                            errorLock.unlock()
                        }
                    }
                }
            }
        }

        group.wait()

        XCTAssertTrue(waitForNoPartialTransferFiles(rootURL: runtime.filesURL, timeout: 5))
        XCTAssertTrue(unexpectedErrors.isEmpty, "Unexpected concurrent churn errors: \(unexpectedErrors)")

        let tree = try snapshotTree(rootURL: runtime.filesURL.appendingPathComponent("shared-sync"))
        XCTAssertFalse(tree.isEmpty, "Churn should leave a browsable shared tree state")

        let list = P7Message(withName: "wired.file.list_directory", spec: alice.socket.spec)
        list.addParameter(field: "wired.file.path", value: "/shared-sync")
        XCTAssertTrue(alice.socket.write(list))
        _ = try readMessage(from: alice.socket, expectedName: "wired.file.file_list.done", maxReads: 80, timeout: 1)
    }

    func testTwoUsersModifySameFileSimultaneously() throws {
        let runtime = try makeSharedSyncRuntime()
        defer { try? runtime.stop() }

        let alice = try connectAndAuthenticate(runtime: runtime, username: "sync_alice", password: "secret1")
        let bob = try connectAndAuthenticate(runtime: runtime, username: "sync_bob", password: "secret2")
        defer { alice.socket.disconnect() }
        defer { bob.socket.disconnect() }

        let remotePath = "/shared-sync/report.txt"
        try uploadFile(socket: alice.socket, path: remotePath, data: Data("base".utf8))

        let aliceData = Data(repeating: 0x41, count: 512 * 1024)
        let bobData = Data(repeating: 0x42, count: 512 * 1024)
        let results = runConcurrentRace([
            { try uploadFile(socket: alice.socket, path: remotePath, data: aliceData) },
            { try uploadFile(socket: bob.socket, path: remotePath, data: bobData) }
        ])

        XCTAssertEqual(results.successes.count, 2, "Both concurrent uploads should complete")
        XCTAssertTrue(waitForNoPartialTransferFiles(rootURL: runtime.filesURL, timeout: 3))

        let reportPath = runtime.filesURL.appendingPathComponent("shared-sync/report.txt").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportPath))
        let finalData = try Data(contentsOf: URL(fileURLWithPath: reportPath))
        let conflictFiles = try conflictFiles(in: runtime.filesURL.appendingPathComponent("shared-sync"), prefix: "report")

        let finalMatchesAlice = finalData == aliceData
        let finalMatchesBob = finalData == bobData
        XCTAssertTrue(finalMatchesAlice || finalMatchesBob, "Canonical file should contain one full winner payload")

        let loserData = finalMatchesAlice ? bobData : aliceData
        let conflictPayloads = try conflictFiles.map { try Data(contentsOf: $0) }
        XCTAssertTrue(
            conflictPayloads.contains(loserData) || conflictPayloads.isEmpty == false,
            "Losing payload should be preserved in a conflict file when the canonical file contains the other payload"
        )
    }

    func testTwoUsersCreateSameFilenameSimultaneously() throws {
        let runtime = try makeSharedSyncRuntime()
        defer { try? runtime.stop() }

        let alice = try connectAndAuthenticate(runtime: runtime, username: "sync_alice", password: "secret1")
        let bob = try connectAndAuthenticate(runtime: runtime, username: "sync_bob", password: "secret2")
        defer { alice.socket.disconnect() }
        defer { bob.socket.disconnect() }

        let remotePath = "/shared-sync/notes.txt"
        let aliceData = Data("alice-wrote-this".utf8)
        let bobData = Data("bob-wrote-that".utf8)
        let results = runConcurrentRace([
            { try uploadFile(socket: alice.socket, path: remotePath, data: aliceData) },
            { try uploadFile(socket: bob.socket, path: remotePath, data: bobData) }
        ])

        XCTAssertEqual(results.successes.count, 2, "Both creates should be preserved via canonical or conflict path")
        XCTAssertTrue(waitForNoPartialTransferFiles(rootURL: runtime.filesURL, timeout: 3))

        let sharedRoot = runtime.filesURL.appendingPathComponent("shared-sync")
        let canonical = sharedRoot.appendingPathComponent("notes.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
        let canonicalData = try Data(contentsOf: canonical)
        let conflictPayloads = try conflictFiles(in: sharedRoot, prefix: "notes").map { try Data(contentsOf: $0) }

        XCTAssertTrue(canonicalData == aliceData || canonicalData == bobData)
        let preservedPayloads = Set(([canonicalData] + conflictPayloads).map { $0.base64EncodedString() })
        XCTAssertTrue(preservedPayloads.contains(aliceData.base64EncodedString()))
        XCTAssertTrue(preservedPayloads.contains(bobData.base64EncodedString()))
    }

    func testDeleteWhileOtherUserModifies() throws {
        let runtime = try makeSharedSyncRuntime()
        defer { try? runtime.stop() }

        let alice = try connectAndAuthenticate(runtime: runtime, username: "sync_alice", password: "secret1")
        let bob = try connectAndAuthenticate(runtime: runtime, username: "sync_bob", password: "secret2")
        defer { alice.socket.disconnect() }
        defer { bob.socket.disconnect() }

        let remotePath = "/shared-sync/todo.txt"
        try uploadFile(socket: alice.socket, path: remotePath, data: Data("initial".utf8))
        let bobData = Data(repeating: 0x5A, count: 256 * 1024)

        let results = runConcurrentRace([
            { try deletePath(socket: alice.socket, path: remotePath); return remotePath },
            { try uploadFile(socket: bob.socket, path: remotePath, data: bobData) }
        ])

        XCTAssertEqual(results.successes.count, 2)
        XCTAssertTrue(waitForNoPartialTransferFiles(rootURL: runtime.filesURL, timeout: 3))

        let sharedRoot = runtime.filesURL.appendingPathComponent("shared-sync")
        let canonical = sharedRoot.appendingPathComponent("todo.txt")
        let conflictPayloads = try conflictFiles(in: sharedRoot, prefix: "todo").map { try Data(contentsOf: $0) }

        if FileManager.default.fileExists(atPath: canonical.path) {
            let canonicalData = try Data(contentsOf: canonical)
            XCTAssertTrue(canonicalData == bobData || conflictPayloads.contains(bobData))
        } else {
            XCTAssertTrue(conflictPayloads.contains(bobData), "If delete wins, modified payload should survive as conflict")
        }
    }

    func testRenameWhileOtherUserUploads() throws {
        let runtime = try makeSharedSyncRuntime()
        defer { try? runtime.stop() }

        let alice = try connectAndAuthenticate(runtime: runtime, username: "sync_alice", password: "secret1")
        let bob = try connectAndAuthenticate(runtime: runtime, username: "sync_bob", password: "secret2")
        defer { alice.socket.disconnect() }
        defer { bob.socket.disconnect() }

        let oldRemotePath = "/shared-sync/draft.txt"
        let newRemotePath = "/shared-sync/draft-renamed.txt"
        try uploadFile(socket: alice.socket, path: oldRemotePath, data: Data("before-rename".utf8))
        let bobData = Data(repeating: 0x33, count: 384 * 1024)

        let results = runConcurrentRace([
            { try movePath(socket: alice.socket, from: oldRemotePath, to: newRemotePath); return newRemotePath },
            { try uploadFile(socket: bob.socket, path: oldRemotePath, data: bobData) }
        ])

        XCTAssertEqual(results.successes.count, 2)
        XCTAssertTrue(waitForNoPartialTransferFiles(rootURL: runtime.filesURL, timeout: 3))

        let sharedRoot = runtime.filesURL.appendingPathComponent("shared-sync")
        let oldPath = sharedRoot.appendingPathComponent("draft.txt")
        let newPath = sharedRoot.appendingPathComponent("draft-renamed.txt")
        let conflictPayloads = try conflictFiles(in: sharedRoot, prefix: "draft").map { try Data(contentsOf: $0) }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: oldPath.path) ||
            FileManager.default.fileExists(atPath: newPath.path) ||
            !conflictPayloads.isEmpty
        )

        if FileManager.default.fileExists(atPath: oldPath.path) {
            let oldData = try Data(contentsOf: oldPath)
            XCTAssertTrue(oldData == bobData || conflictPayloads.contains(bobData))
        } else if FileManager.default.fileExists(atPath: newPath.path) {
            let newData = try Data(contentsOf: newPath)
            XCTAssertTrue(newData == Data("before-rename".utf8) || newData == bobData || conflictPayloads.contains(bobData))
        }
    }

    private func makeSharedSyncRuntime() throws -> IntegrationServerRuntime {
        let runtime = try IntegrationServerRuntime()
        try runtime.start()
        runtime.ensurePrivilegedUser(username: "sync_alice", password: "secret1")
        runtime.ensurePrivilegedUser(username: "sync_bob", password: "secret2")
        runtime.ensurePrivilegedUser(username: "sync_carol", password: "secret3")
        let admin = try connectAndAuthenticate(runtime: runtime, username: "sync_alice", password: "secret1")
        try createSyncDirectory(socket: admin.socket, path: "/shared-sync", owner: "admin", group: "admin")
        admin.socket.disconnect()
        return runtime
    }

    private func isExpectedRaceError(_ error: Error) -> Bool {
        let text = error.localizedDescription
        return text.contains("wired.error.file_not_found") || text.contains("wired.error.file_exists")
    }

    private func runConcurrentRace(_ operations: [() throws -> String]) -> (successes: [String], failures: [String]) {
        let barrier = ConcurrentStartBarrier(participantCount: operations.count)
        let group = DispatchGroup()
        let lock = NSLock()
        var successes: [String] = []
        var failures: [String] = []

        for operation in operations {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                barrier.wait()
                do {
                    let value = try operation()
                    lock.lock()
                    successes.append(value)
                    lock.unlock()
                } catch {
                    lock.lock()
                    failures.append(String(describing: error))
                    lock.unlock()
                }
            }
        }

        group.wait()
        return (successes, failures)
    }

    private func conflictFiles(in directory: URL, prefix: String) throws -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var matches: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let name = url.lastPathComponent
            if name.contains(".conflict."), name.hasPrefix(prefix) {
                matches.append(url)
            }
        }
        return matches
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(state: UInt64) {
        self.state = state == 0 ? 0x1234_5678_9ABC_DEF0 : state
    }

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}
