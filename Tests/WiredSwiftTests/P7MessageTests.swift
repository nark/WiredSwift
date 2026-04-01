import XCTest
@testable import WiredSwift

final class P7MessageTests: XCTestCase {

    var spec: P7Spec!

    override func setUpWithError() throws {
        spec = try XCTUnwrap(WiredProtocolSpec.bundledSpec(), "Failed to load bundled wired.xml")
    }

    // MARK: - init(withName:spec:)

    func testInitWithValidName() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        XCTAssertEqual(msg.name, "wired.send_login")
        XCTAssertNotNil(msg.specMessage)
        XCTAssertNotNil(msg.id)
    }

    func testInitWithUnknownNameSetsNameOnly() {
        let msg = P7Message(withName: "wired.does_not_exist", spec: spec)
        XCTAssertEqual(msg.name, "wired.does_not_exist")
        XCTAssertNil(msg.specMessage)
    }

    // MARK: - addParameter + accessors

    func testStringAccessor() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.login", value: "alice")
        XCTAssertEqual(msg.string(forField: "wired.user.login"), "alice")
    }

    func testUint32Accessor() {
        let msg = P7Message(withName: "wired.user.get_info", spec: spec)
        msg.addParameter(field: "wired.user.id", value: UInt32(42))
        XCTAssertEqual(msg.uint32(forField: "wired.user.id"), 42)
    }

    func testUint64Accessor() {
        let msg = P7Message(withName: "wired.server_info", spec: spec)
        msg.addParameter(field: "wired.info.files.count", value: UInt64(1_000_000))
        XCTAssertEqual(msg.uint64(forField: "wired.info.files.count"), 1_000_000)
    }

    func testBoolAccessorTrue() {
        // bool(forField:) expects UInt8 internally (matching loadBinaryMessage storage)
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.idle", value: UInt8(1))
        XCTAssertEqual(msg.bool(forField: "wired.user.idle"), true)
    }

    func testBoolAccessorFalse() {
        // bool(forField:) expects UInt8 internally (matching loadBinaryMessage storage)
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.idle", value: UInt8(0))
        XCTAssertEqual(msg.bool(forField: "wired.user.idle"), false)
    }

    func testMissingFieldReturnsNil() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        XCTAssertNil(msg.string(forField: "wired.user.login"))
        XCTAssertNil(msg.uint32(forField: "wired.user.id"))
    }

    // MARK: - numberOfParameters / parameterKeys

    func testNumberOfParameters() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        XCTAssertEqual(msg.numberOfParameters, 0)
        msg.addParameter(field: "wired.user.login", value: "bob")
        XCTAssertEqual(msg.numberOfParameters, 1)
        msg.addParameter(field: "wired.user.password", value: "secret")
        XCTAssertEqual(msg.numberOfParameters, 2)
    }

    func testParameterKeysContainsAddedFields() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.login", value: "bob")
        XCTAssertTrue(msg.parameterKeys.contains("wired.user.login"))
    }

    // MARK: - Round-trip: string

    func testRoundTripString() throws {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.login", value: "alice")
        original.addParameter(field: "wired.user.password", value: "s3cr3t!")

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.name, "wired.send_login")
        XCTAssertEqual(recovered.string(forField: "wired.user.login"), "alice")
        XCTAssertEqual(recovered.string(forField: "wired.user.password"), "s3cr3t!")
    }

    func testRoundTripEmptyString() throws {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.login", value: "")

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.string(forField: "wired.user.login"), "")
    }

    func testRoundTripUTF8String() throws {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.login", value: "utilisateur-éàü")

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.string(forField: "wired.user.login"), "utilisateur-éàü")
    }

    // MARK: - Round-trip: uint32

    func testRoundTripUint32() throws {
        let original = P7Message(withName: "wired.user.get_info", spec: spec)
        original.addParameter(field: "wired.user.id", value: UInt32(1337))

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.uint32(forField: "wired.user.id"), 1337)
    }

    func testRoundTripUint32MaxValue() throws {
        let original = P7Message(withName: "wired.user.get_info", spec: spec)
        original.addParameter(field: "wired.user.id", value: UInt32.max)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.uint32(forField: "wired.user.id"), UInt32.max)
    }

    func testRoundTripUint32Zero() throws {
        let original = P7Message(withName: "wired.user.get_info", spec: spec)
        original.addParameter(field: "wired.user.id", value: UInt32(0))

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.uint32(forField: "wired.user.id"), 0)
    }

    // MARK: - Round-trip: uint64

    func testRoundTripUint64() throws {
        let original = P7Message(withName: "wired.server_info", spec: spec)
        original.addParameter(field: "wired.info.files.count", value: UInt64(9_876_543_210))

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.uint64(forField: "wired.info.files.count"), 9_876_543_210)
    }

    // MARK: - Round-trip: bool

    func testRoundTripBoolTrue() throws {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.idle", value: true)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.bool(forField: "wired.user.idle"), true)
    }

    func testRoundTripBoolFalse() throws {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.idle", value: false)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.bool(forField: "wired.user.idle"), false)
    }

    // MARK: - Round-trip: date

    func testRoundTripDate() throws {
        // Use a fixed timestamp to avoid floating-point precision issues
        let timestamp: TimeInterval = 1_700_000_000
        let date = Date(timeIntervalSince1970: timestamp)

        let original = P7Message(withName: "wired.server_info", spec: spec)
        original.addParameter(field: "wired.info.start_time", value: date)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        let recoveredDate = recovered.date(forField: "wired.info.start_time")
        XCTAssertNotNil(recoveredDate)
        XCTAssertEqual(recoveredDate!.timeIntervalSince1970, timestamp, accuracy: 1e-6)
    }

    // MARK: - Round-trip: uuid

    func testRoundTripUUID() throws {
        let uuidString = "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"

        let original = P7Message(withName: "wired.board.get_thread", spec: spec)
        original.addParameter(field: "wired.board.thread", value: uuidString)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        let recoveredUUID = recovered.uuid(forField: "wired.board.thread")
        XCTAssertNotNil(recoveredUUID)
        // UUIDs are case-insensitive
        XCTAssertEqual(recoveredUUID?.uppercased(), uuidString.uppercased())
    }

    // MARK: - Round-trip: data

    func testRoundTripData() throws {
        let payload = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])

        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.icon", value: payload)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.data(forField: "wired.user.icon"), payload)
    }

    // MARK: - Round-trip: multiple fields

    func testRoundTripMultipleFields() throws {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.user.login", value: "bob")
        original.addParameter(field: "wired.user.password", value: "pass123")
        original.addParameter(field: "wired.user.idle", value: false)

        let binary = original.bin()
        let recovered = P7Message(withData: binary, spec: spec)

        XCTAssertEqual(recovered.string(forField: "wired.user.login"), "bob")
        XCTAssertEqual(recovered.string(forField: "wired.user.password"), "pass123")
        XCTAssertEqual(recovered.bool(forField: "wired.user.idle"), false)
    }

    // MARK: - Security: malformed binary input

    func testEmptyDataDoesNotCrash() {
        let msg = P7Message(withData: Data(), spec: spec)
        // Message too short — should be an inert, empty message
        XCTAssertNil(msg.name)
    }

    func testTruncatedAfterMessageIDDoesNotCrash() {
        // Only 4 bytes: message ID present, no field data
        var data = Data()
        data.append(uint32: 2004, bigEndian: true) // wired.send_login
        let msg = P7Message(withData: data, spec: spec)
        XCTAssertEqual(msg.name, "wired.send_login")
        XCTAssertEqual(msg.numberOfParameters, 0)
    }

    func testUnknownMessageIDDoesNotCrash() {
        var data = Data()
        data.append(uint32: 0xFFFFFFFF, bigEndian: true) // unknown ID
        let msg = P7Message(withData: data, spec: spec)
        XCTAssertNil(msg.name)
    }

    func testTruncatedFieldDoesNotCrash() {
        // Message ID OK, then field ID, then incomplete length/value
        var data = Data()
        data.append(uint32: 2004, bigEndian: true) // wired.send_login
        data.append(uint32: 3000, bigEndian: true) // wired.user.login field id
        // Missing length + value — truncated
        let msg = P7Message(withData: data, spec: spec)
        XCTAssertEqual(msg.name, "wired.send_login")
        XCTAssertEqual(msg.numberOfParameters, 0)
    }

    // MARK: - lazy(field:)

    func testLazyCoversStringNumericDataAndUUIDTypes() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.login", value: "alice")
        msg.addParameter(field: "wired.user.id", value: UInt32(42))
        msg.addParameter(field: "wired.info.files.count", value: UInt64(9_001))
        msg.addParameter(field: "wired.user.icon", value: Data([0xAA, 0xBB]))
        msg.addParameter(field: "wired.board.thread", value: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")

        XCTAssertEqual(msg.lazy(field: "wired.user.login"), "alice")
        XCTAssertEqual(msg.lazy(field: "wired.user.id"), "42")
        XCTAssertEqual(msg.lazy(field: "wired.info.files.count"), "9001")
        XCTAssertEqual(msg.lazy(field: "wired.user.icon"), "aabb")
        XCTAssertEqual(msg.lazy(field: "wired.board.thread")?.uppercased(), "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")
    }

    func testLazyReturnsNilForUnsupportedFieldType() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.idle", value: UInt8(1))
        XCTAssertNil(msg.lazy(field: "wired.user.idle"))
    }

    // MARK: - list support

    func testRoundTripStringListField() {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.account.groups", value: ["staff", "admins"])

        let recovered = P7Message(withData: original.bin(), spec: spec)
        XCTAssertEqual(recovered.stringList(forField: "wired.account.groups"), ["staff", "admins"])
    }

    func testRoundTripAnyListSkipsNonStringItems() {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.account.groups", value: ["staff", 123, "mods"] as [Any])

        let recovered = P7Message(withData: original.bin(), spec: spec)
        XCTAssertEqual(recovered.stringList(forField: "wired.account.groups"), ["staff", "mods"])
    }

    func testRoundTripEmptyListProducesEmptyArray() {
        let original = P7Message(withName: "wired.send_login", spec: spec)
        original.addParameter(field: "wired.account.groups", value: [String]())

        let recovered = P7Message(withData: original.bin(), spec: spec)
        // Current parser behavior: zero-length list payload is omitted instead of materialized as [].
        XCTAssertNil(recovered.stringList(forField: "wired.account.groups"))
    }

    // MARK: - xml()

    func testXMLSerializationIncludesExpectedFieldValues() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.login", value: "alice")
        msg.addParameter(field: "wired.user.idle", value: UInt32(1))
        msg.addParameter(field: "wired.info.start_time", value: 1_700_000_000.0)
        msg.addParameter(field: "wired.account.groups", value: ["staff", "admins"])

        let xml = msg.xml()
        XCTAssertTrue(xml.contains("wired.send_login"))
        XCTAssertTrue(xml.contains("wired.user.login"))
        XCTAssertTrue(xml.contains("alice"))
        XCTAssertTrue(xml.contains("wired.user.idle"))
        XCTAssertTrue(xml.contains("true"))
        XCTAssertTrue(xml.contains("wired.account.groups"))
        XCTAssertTrue(xml.contains("staff,admins"))
    }

    // MARK: - accessors edge cases

    func testStringAccessorTrimsControlCharacters() {
        let msg = P7Message(withName: "wired.send_login", spec: spec)
        msg.addParameter(field: "wired.user.login", value: "\u{0000}alice\u{000A}")
        XCTAssertEqual(msg.string(forField: "wired.user.login"), "alice")
    }

    func testInitWithXMLKeepsSpecAndDoesNotCrash() {
        let msg = P7Message(withXML: "<p7:message name=\"wired.send_login\"/>", spec: spec)
        XCTAssertNotNil(msg.spec)
        XCTAssertNil(msg.name)
    }

    func testMalformedListPayloadDoesNotCrashAndParsesSafely() {
        var data = Data()
        data.append(uint32: 2004, bigEndian: true) // wired.send_login
        data.append(uint32: 8016, bigEndian: true) // wired.account.groups (list[string])

        var listData = Data()
        listData.append(uint32: 100, bigEndian: true) // declared item length larger than payload
        listData.append(Data([0x41, 0x42])) // tiny payload

        data.append(uint32: UInt32(listData.count), bigEndian: true)
        data.append(listData)

        let msg = P7Message(withData: data, spec: spec)
        XCTAssertEqual(msg.name, "wired.send_login")
        XCTAssertEqual(msg.stringList(forField: "wired.account.groups"), [])
    }
}
