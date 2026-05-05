import XCTest
@testable import WiredSwift

final class CompatibilityTests: XCTestCase {

    var spec: P7Spec!

    override func setUpWithError() throws {
        spec = try XCTUnwrap(P7Spec(withUrl: TestResources.specURL),
                             "Failed to load bundled wired.xml")
    }

    // MARK: - ProtocolVersion

    func testProtocolVersionParsing() {
        XCTAssertEqual(ProtocolVersion("3"), ProtocolVersion(major: 3))
        XCTAssertEqual(ProtocolVersion("3.1"), ProtocolVersion(major: 3, minor: 1))
        XCTAssertEqual(ProtocolVersion("3.1.4"), ProtocolVersion(major: 3, minor: 1, patch: 4))
        XCTAssertNil(ProtocolVersion("garbage"))
        XCTAssertNil(ProtocolVersion(""))
    }

    func testProtocolVersionNumericOrdering() {
        // String comparison would put 3.10 before 3.2 — ours must not.
        XCTAssertLessThan(ProtocolVersion("3.2")!, ProtocolVersion("3.10")!)
        XCTAssertLessThan(ProtocolVersion("3.0.9")!, ProtocolVersion("3.0.10")!)
        XCTAssertLessThan(ProtocolVersion("2.99")!, ProtocolVersion("3.0")!)
    }

    func testProtocolVersionCompatibilityIsMajorOnly() {
        let v3_0 = ProtocolVersion("3.0")!
        let v3_1 = ProtocolVersion("3.1")!
        let v4_0 = ProtocolVersion("4.0")!
        XCTAssertTrue(v3_0.isCompatible(with: v3_1))
        XCTAssertTrue(v3_1.isCompatible(with: v3_0))
        XCTAssertFalse(v3_0.isCompatible(with: v4_0))
    }

    func testProtocolVersionNegotiatedTakesMin() {
        XCTAssertEqual(
            ProtocolVersion.negotiated(ProtocolVersion("3.1")!, ProtocolVersion("3.0")!),
            ProtocolVersion("3.0")!
        )
    }

    // MARK: - P7Spec compatibility

    func testSpecCompatibilityAcceptsSameMajorDifferentMinor() {
        let localVersion = try? XCTUnwrap(spec.protocolVersion)
        XCTAssertNotNil(localVersion)
        // Force a synthetic remote version sharing the same major.
        let major = ProtocolVersion(localVersion!)!.major
        XCTAssertTrue(spec.isCompatibleWithProtocol(withName: "Wired", version: "\(major).999"))
        XCTAssertFalse(spec.isCompatibleWithProtocol(withName: "Wired", version: "\(major + 1).0"))
        XCTAssertFalse(spec.isCompatibleWithProtocol(withName: "NotWired", version: "\(major).0"))
    }

    // MARK: - CompatibilityDiff

    func testIdenticalSpecsProduceEmptyDiff() {
        let diff = CompatibilityDiff.diff(local: spec, remote: spec)
        XCTAssertTrue(diff.isEmpty)
    }

    func testDiffDetectsMissingMessagesAndFields() {
        // Build a stripped-down "older" spec by removing a known v3.1 item.
        let xml = try? XCTUnwrap(spec.xml)
        let stripped = xml!.replacingOccurrences(
            of: "<p7:field name=\"wired.chat.typing\" type=\"bool\" id=\"4006\" version=\"3.1\">",
            with: "<p7:field name=\"wired.chat.typing.removed\" type=\"bool\" id=\"99999\" version=\"3.1\">"
        )

        let older = try? XCTUnwrap(P7Spec(withString: stripped))
        let diff = CompatibilityDiff.diff(local: spec, remote: older!)

        XCTAssertTrue(diff.fieldsUnknownToRemote.contains(4006))
        XCTAssertTrue(diff.fieldsUnknownToLocal.contains(99999))
    }

    // MARK: - Receiver tolerance

    func testUnknownFieldIDInBinaryStreamIsRecordedAndAborts() {
        // Build a real chat send_say message but append a fake TLV with an
        // unknown field ID after the known fields. Since we can't know the
        // type of the unknown field, decoding must abort cleanly with the
        // ID recorded in `unknownFieldIDs`.
        let msg = P7Message(withName: "wired.chat.send_say", spec: spec)
        msg.addParameter(field: "wired.chat.id", value: UInt32(1))
        msg.addParameter(field: "wired.chat.say", value: "hello")

        var bin = msg.bin()
        // Append a TLV with id 0xDEADBEEF and a string-style 4-byte length
        // header — but the decoder won't know it's a string, so it'll bail.
        bin.append(uint32: 0xDEADBEEF, bigEndian: true)
        bin.append(uint32: 4, bigEndian: true)
        bin.append(Data([0xCA, 0xFE, 0xBA, 0xBE]))

        let decoded = P7Message(withData: bin, spec: spec)
        XCTAssertEqual(decoded.name, "wired.chat.send_say")
        XCTAssertEqual(decoded.string(forField: "wired.chat.say"), "hello")
        XCTAssertTrue(decoded.unknownFieldIDs.contains(0xDEADBEEF))
        XCTAssertFalse(decoded.hasUnknownMessageID)
    }

    func testUnknownMessageIDStillExtractsKnownFields() {
        // Manually craft a frame with an unknown message ID (UInt32.max)
        // and a `wired.transaction` field (id 1000, type uint32) so the
        // upper layer can still respond with a transaction-aware error.
        var bin = Data()
        bin.append(uint32: UInt32.max, bigEndian: true)
        bin.append(uint32: 1000, bigEndian: true)
        bin.append(uint32: 42, bigEndian: true)

        let decoded = P7Message(withData: bin, spec: spec)
        XCTAssertTrue(decoded.hasUnknownMessageID)
        XCTAssertNil(decoded.name)
        XCTAssertEqual(decoded.uint32(forField: "wired.transaction"), 42)
    }

    // MARK: - Sender filter

    func testBinOmittingFieldIDsStripsTLVs() {
        let msg = P7Message(withName: "wired.chat.send_say", spec: spec)
        msg.addParameter(field: "wired.chat.id", value: UInt32(1))
        msg.addParameter(field: "wired.chat.say", value: "hello")

        // Find the field id of `wired.chat.say` and omit it.
        let sayFieldID = UInt32(spec.fieldsByName["wired.chat.say"]!.id!)!
        let stripped = msg.bin(omittingFieldIDs: [sayFieldID])

        let decoded = P7Message(withData: stripped, spec: spec)
        XCTAssertEqual(decoded.name, "wired.chat.send_say")
        XCTAssertNil(decoded.string(forField: "wired.chat.say"))
        XCTAssertEqual(decoded.uint32(forField: "wired.chat.id"), 1)
    }
}
