import XCTest
@testable import WiredSwift

final class DataExtensionTests: XCTestCase {

    // MARK: - uint32 big-endian read

    func testUint32FromBigEndianBytes() {
        // 0x00_01_00_00 = 65536 in big-endian
        let data = Data([0x00, 0x01, 0x00, 0x00])
        XCTAssertEqual(data.uint32, 65536)
    }

    func testUint32KnownValue() {
        // 0xDEAD_BEEF big-endian
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(data.uint32, 0xDEADBEEF)
    }

    func testUint32TooShortReturnsNil() {
        let data = Data([0x00, 0x01, 0x02])
        XCTAssertNil(data.uint32)
    }

    func testUint32EmptyReturnsNil() {
        XCTAssertNil(Data().uint32)
    }

    // MARK: - uint64 big-endian read

    func testUint64FromBigEndianBytes() {
        // 1 in big-endian 8 bytes
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
        XCTAssertEqual(data.uint64, 1)
    }

    func testUint64KnownValue() {
        let data = Data([0x00, 0x00, 0x00, 0x00, 0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(data.uint64, 0xDEADBEEF)
    }

    func testUint64TooShortReturnsNil() {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        XCTAssertNil(data.uint64)
    }

    // MARK: - append(uint32:bigEndian:)

    func testAppendUint32BigEndian() {
        var data = Data()
        data.append(uint32: 0xDEADBEEF, bigEndian: true)
        XCTAssertEqual(data, Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testAppendUint32Zero() {
        var data = Data()
        data.append(uint32: 0, bigEndian: true)
        XCTAssertEqual(data, Data([0x00, 0x00, 0x00, 0x00]))
    }

    func testAppendUint32RoundTrip() {
        let original: UInt32 = 123456789
        var data = Data()
        data.append(uint32: original, bigEndian: true)
        XCTAssertEqual(data.uint32, original)
    }

    // MARK: - append(uint64:bigEndian:)

    func testAppendUint64BigEndian() {
        var data = Data()
        data.append(uint64: 0x0102030405060708, bigEndian: true)
        XCTAssertEqual(data, Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
    }

    func testAppendUint64RoundTrip() {
        let original: UInt64 = 9876543210
        var data = Data()
        data.append(uint64: original, bigEndian: true)
        XCTAssertEqual(data.uint64, original)
    }

    // MARK: - append(uint8:bigEndian:)

    func testAppendUint8() {
        var data = Data()
        data.append(uint8: 0xFF, bigEndian: true)
        XCTAssertEqual(data, Data([0xFF]))
        XCTAssertEqual(data.uint8, 0xFF)
    }

    // MARK: - double round-trip

    func testDoubleRoundTrip() {
        let original: Double = 3.14159265358979
        var data = Data()
        data.append(double: original, bigEndian: true)
        let recovered = data.double
        XCTAssertNotNil(recovered)
        XCTAssertEqual(recovered!, original, accuracy: 1e-15)
    }

    func testDoubleTooShortReturnsNil() {
        XCTAssertNil(Data([0x00, 0x01, 0x02]).double)
    }

    // MARK: - toHex()

    func testToHexKnownValue() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertEqual(data.toHex(), "deadbeef")
    }

    func testToHexEmpty() {
        XCTAssertEqual(Data().toHex(), "")
    }

    func testToHexAllZeros() {
        let data = Data([0x00, 0x00, 0x00])
        XCTAssertEqual(data.toHex(), "000000")
    }

    // MARK: - Data(from:) + to(type:) generic round-trip

    func testGenericInt32RoundTrip() {
        let original: Int32 = -42
        let data = Data(from: original)
        let recovered = data.to(type: Int32.self)
        XCTAssertEqual(recovered, original)
    }

    // MARK: - uuid

    func testUuidFromSixteenBytes() {
        let bytes: [UInt8] = [
            0x6B, 0xA7, 0xB8, 0x10, 0x9D, 0xAD, 0x11, 0xD1,
            0x80, 0xB4, 0x00, 0xC0, 0x4F, 0xD4, 0x30, 0xC8
        ]
        let data = Data(bytes)
        XCTAssertNotNil(data.uuid)
    }

    func testUuidTooShortReturnsNil() {
        XCTAssertNil(Data([0x00, 0x01]).uuid)
    }
}
