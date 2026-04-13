import XCTest
@testable import wired3Lib

final class FilesystemMonitorTests: XCTestCase {
    func testObservedPathsAreDebouncedIntoSingleBatch() {
        let expectation = expectation(description: "debounced filesystem events")
        expectation.expectedFulfillmentCount = 1

        var receivedBatches: [[String]] = []
        let monitor = FilesystemMonitor(path: "/tmp", debounceInterval: 0.05) { paths in
            receivedBatches.append(paths)
            expectation.fulfill()
        }
        defer { monitor.stop() }

        monitor.processObservedPaths(["/tmp/a.txt"])
        monitor.processObservedPaths(["/tmp/b.txt", "/tmp/a.txt"])

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(receivedBatches.count, 1)
        XCTAssertEqual(Set(receivedBatches[0]), Set(["/tmp/a.txt", "/tmp/b.txt"]))
    }
}
