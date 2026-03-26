import XCTest
@testable import WiredSwift

final class CollectionExtensionsTests: XCTestCase {
    private struct TestBits: OptionSet, Collection {
        typealias RawValue = UInt8
        typealias Index = IndexWithEnd<RawValue>

        let rawValue: RawValue

        init(rawValue: RawValue) {
            self.rawValue = rawValue
        }

        static let first = TestBits(rawValue: 1 << 0)
        static let third = TestBits(rawValue: 1 << 2)
        static let fifth = TestBits(rawValue: 1 << 4)
    }

    func testChunkedSplitsIntoEvenGroups() {
        let values = [1, 2, 3, 4, 5, 6]
        XCTAssertEqual(values.chunked(into: 2).map(\.count), [2, 2, 2])
    }

    func testChunkedKeepsRemainderInLastChunk() {
        let values = [1, 2, 3, 4, 5]
        XCTAssertEqual(values.chunked(into: 2), [[1, 2], [3, 4], [5]])
    }

    func testAverageForBinaryIntegerArray() {
        XCTAssertEqual([2, 4, 6, 8].average, 5.0)
    }

    func testAverageForBinaryIntegerEmptyArrayIsZero() {
        let values: [Int] = []
        XCTAssertEqual(values.average, 0.0)
    }

    func testAverageForBinaryFloatingPointArray() {
        XCTAssertEqual([1.5, 2.5, 3.5].average, 2.5, accuracy: 0.0001)
    }

    func testAverageForBinaryFloatingPointEmptyArrayIsZero() {
        let values: [Double] = []
        XCTAssertEqual(values.average, 0.0)
    }

    func testIndexWithEndComparableOrdering() {
        XCTAssertTrue(IndexWithEnd<UInt8>.element(1) < .element(2))
        XCTAssertTrue(IndexWithEnd<UInt8>.element(2) < .end)
        XCTAssertFalse(IndexWithEnd<UInt8>.end < .element(1))
    }

    func testOptionSetCollectionStartAndEndIndex() {
        let bits: TestBits = [.first, .third]
        XCTAssertEqual(bits.startIndex, .element(1))
        XCTAssertEqual(bits.endIndex, .end)
    }

    func testOptionSetCollectionIsEmptyAndCount() {
        XCTAssertTrue(TestBits(rawValue: 0).isEmpty)
        XCTAssertEqual(TestBits(rawValue: 0).count, 0)
        XCTAssertEqual(TestBits(rawValue: 0b1_0101).count, 3)
    }

    func testOptionSetCollectionSubscriptAndIndexAfter() {
        let bits: TestBits = [.first, .third, .fifth]
        var index = bits.startIndex
        var collected: [UInt8] = []

        while index != bits.endIndex {
            collected.append(bits[index].rawValue)
            index = bits.index(after: index)
        }

        XCTAssertEqual(collected, [1, 4, 16])
    }
}
