import Foundation
import XCTest
@testable import WiredSwift

final class ConfigFileDefaultsTests: XCTestCase {
    func testAddsSecuritySectionWhenMissing() throws {
        let fileURL = try makeTempConfigFile(contents: """
[server]
port = 4871
""")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertTrue(ConfigFileDefaults.ensureStrictIdentitySetting(at: fileURL.path))

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("[security]\nstrict_identity = yes"))
    }

    func testInsertsMissingKeyInsideExistingSecuritySection() throws {
        let fileURL = try makeTempConfigFile(contents: """
[server]
port = 4871

[security]
; keep this comment

[advanced]
cipher = SECURE_ONLY
""")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertTrue(ConfigFileDefaults.ensureStrictIdentitySetting(at: fileURL.path))

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains("[security]\n; keep this comment\n\nstrict_identity = yes\n[advanced]"))
    }

    func testDoesNothingWhenStrictIdentityAlreadyExists() throws {
        let original = """
[security]
strict_identity = no
"""
        let fileURL = try makeTempConfigFile(contents: original)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertFalse(ConfigFileDefaults.ensureStrictIdentitySetting(at: fileURL.path))

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(contents, original)
    }

    private func makeTempConfigFile(contents: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ini")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    static var allTests = [
        ("testAddsSecuritySectionWhenMissing", testAddsSecuritySectionWhenMissing),
        ("testInsertsMissingKeyInsideExistingSecuritySection", testInsertsMissingKeyInsideExistingSecuritySection),
        ("testDoesNothingWhenStrictIdentityAlreadyExists", testDoesNothingWhenStrictIdentityAlreadyExists),
    ]
}
