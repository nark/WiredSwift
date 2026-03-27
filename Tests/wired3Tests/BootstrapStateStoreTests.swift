import XCTest
@testable import wired3Lib

final class BootstrapStateStoreTests: XCTestCase {
    func testIsCompletedReturnsFalseWhenStateFileIsMissing() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let store = BootstrapStateStore(workingDirectoryPath: tempDir.path)
        XCTAssertFalse(store.isCompleted("seed.a"))
    }

    func testMarkCompletedPersistsAcrossStoreInstances() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let firstStore = BootstrapStateStore(workingDirectoryPath: tempDir.path)
        firstStore.markCompleted("seed.persisted")
        XCTAssertTrue(firstStore.isCompleted("seed.persisted"))

        let secondStore = BootstrapStateStore(workingDirectoryPath: tempDir.path)
        XCTAssertTrue(secondStore.isCompleted("seed.persisted"))
        XCTAssertFalse(secondStore.isCompleted("seed.other"))
    }

    func testMarkCompletedIsIdempotentAndDoesNotDuplicateSeed() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let store = BootstrapStateStore(workingDirectoryPath: tempDir.path)
        store.markCompleted("seed.once")
        store.markCompleted("seed.once")

        let statePath = tempDir.appendingPathComponent(".wired-bootstrap-state.json").path
        let data = try Data(contentsOf: URL(fileURLWithPath: statePath))
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let completed = payload?["completedSeeds"] as? [String] ?? []

        XCTAssertEqual(completed.filter { $0 == "seed.once" }.count, 1)
    }

    func testInvalidStateFileFallsBackToEmptyState() throws {
        let tempDir = try makeTemporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let statePath = tempDir.appendingPathComponent(".wired-bootstrap-state.json")
        try Data("not json".utf8).write(to: statePath)

        let store = BootstrapStateStore(workingDirectoryPath: tempDir.path)
        XCTAssertFalse(store.isCompleted("seed.invalid"))
    }
}
