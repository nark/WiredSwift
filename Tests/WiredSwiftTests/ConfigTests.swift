import Foundation
import XCTest
@testable import WiredSwift

final class ConfigTests: XCTestCase {
    func testSaveUpdatesExistingConfigFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ini")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try """
[server]
name = Original
"""
            .write(to: fileURL, atomically: false, encoding: .utf8)

        let config = Config(withPath: fileURL.path)
        XCTAssertTrue(config.load())

        config["server", "name"] = "Updated"

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("name = Updated"))
    }
}
