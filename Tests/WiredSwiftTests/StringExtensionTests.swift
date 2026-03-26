import XCTest
@testable import WiredSwift

final class StringExtensionTests: XCTestCase {

    // MARK: - nullTerminated

    func testNullTerminatedAppendsNullByte() {
        let result = "hello".nullTerminated
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.last, 0x00)
    }

    func testNullTerminatedLength() {
        let str = "abc"
        let result = str.nullTerminated
        XCTAssertEqual(result!.count, str.utf8.count + 1)
    }

    func testNullTerminatedEmptyString() {
        let result = "".nullTerminated
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.count, 1)
        XCTAssertEqual(result!.first, 0x00)
    }

    // MARK: - deletingPrefix

    func testDeletingPrefixWithMatchingPrefix() {
        XCTAssertEqual("wired.chat.say".deletingPrefix("wired."), "chat.say")
    }

    func testDeletingPrefixWithoutMatchingPrefix() {
        XCTAssertEqual("chat.say".deletingPrefix("wired."), "chat.say")
    }

    func testDeletingPrefixEmptyPrefix() {
        XCTAssertEqual("hello".deletingPrefix(""), "hello")
    }

    func testDeletingPrefixPrefixLongerThanString() {
        XCTAssertEqual("hi".deletingPrefix("hello"), "hi")
    }

    // MARK: - isBlank

    func testIsBlankWithEmptyString() {
        XCTAssertTrue("".isBlank)
    }

    func testIsBlankWithSpaces() {
        XCTAssertTrue("   ".isBlank)
    }

    func testIsBlankWithTabs() {
        XCTAssertTrue("\t\t".isBlank)
    }

    func testIsBlankWithNonBlank() {
        XCTAssertFalse("hello".isBlank)
    }

    func testIsBlankWithMixedWhitespaceAndText() {
        XCTAssertFalse("  a  ".isBlank)
    }

    // MARK: - Optional<String>.isBlank

    func testOptionalNilIsBlank() {
        let s: String? = nil
        XCTAssertTrue(s.isBlank)
    }

    func testOptionalEmptyStringIsBlank() {
        let s: String? = ""
        XCTAssertTrue(s.isBlank)
    }

    func testOptionalNonBlankIsNotBlank() {
        let s: String? = "hello"
        XCTAssertFalse(s.isBlank)
    }

    // MARK: - dataFromHexadecimalString

    func testValidHexString() {
        let data = "deadbeef".dataFromHexadecimalString()
        XCTAssertNotNil(data)
        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testValidHexStringUppercase() {
        let data = "DEADBEEF".dataFromHexadecimalString()
        XCTAssertNotNil(data)
        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testHexStringWithAngleBracketsAndSpaces() {
        let data = "<DE AD BE EF>".dataFromHexadecimalString()
        XCTAssertNotNil(data)
        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testOddLengthHexStringReturnsNil() {
        XCTAssertNil("abc".dataFromHexadecimalString())
    }

    func testInvalidHexCharsReturnNil() {
        XCTAssertNil("zzzz".dataFromHexadecimalString())
    }

    // NOTE: "".dataFromHexadecimalString() triggers a String index out-of-bounds crash
    // in the current implementation (the while loop doesn't guard against empty input).
    // A fix should be applied to the source before enabling an empty-string test.

    // MARK: - Path utilities

    func testLastPathComponent() {
        XCTAssertEqual("/foo/bar/baz.txt".lastPathComponent, "baz.txt")
    }

    func testPathExtension() {
        XCTAssertEqual("archive.tar.gz".pathExtension, "gz")
    }

    func testStringByDeletingLastPathComponent() {
        XCTAssertEqual("/foo/bar/baz.txt".stringByDeletingLastPathComponent, "/foo/bar")
    }

    func testStringByDeletingPathExtension() {
        XCTAssertEqual("document.pdf".stringByDeletingPathExtension, "document")
    }

    func testStringByAppendingPathComponent() {
        XCTAssertEqual("/foo/bar".stringByAppendingPathComponent(path: "baz"), "/foo/bar/baz")
    }

    func testStringByAppendingPathExtension() {
        XCTAssertEqual("document".stringByAppendingPathExtension(ext: "pdf"), "document.pdf")
    }
}
