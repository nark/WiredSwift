import XCTest
@testable import WiredSwift

final class P7SpecMetadataTests: XCTestCase {
    func testSpecTypeMappingSupportsAliasesAndUnknownReturnsNil() {
        XCTAssertEqual(P7SpecType.specType(forString: "bool"), .bool)
        XCTAssertEqual(P7SpecType.specType(forString: "enum"), .enum32)
        XCTAssertEqual(P7SpecType.specType(forString: "enum32"), .enum32)
        XCTAssertEqual(P7SpecType.specType(forString: "oobdata"), .oobdata)
        XCTAssertNil(P7SpecType.specType(forString: "definitely-unknown"))
    }

    func testSpecTypeSizeForFixedAndVariableLengthTypes() {
        XCTAssertEqual(P7SpecType.size(forType: .bool), 1)
        XCTAssertEqual(P7SpecType.size(forType: .uint32), 4)
        XCTAssertEqual(P7SpecType.size(forType: .uint64), 8)
        XCTAssertEqual(P7SpecType.size(forType: .uuid), 16)
        XCTAssertEqual(P7SpecType.size(forType: .string), 0)
        XCTAssertEqual(P7SpecType.size(forType: .data), 0)
        XCTAssertEqual(P7SpecType.size(forType: .list), 0)
    }

    func testSpecFieldHasExplicitLengthForStringDataAndListOnly() {
        let spec = P7Spec(withPath: nil)
        let stringField = P7SpecField(name: "name", spec: spec, attributes: ["type": "string"])
        let dataField = P7SpecField(name: "payload", spec: spec, attributes: ["type": "data"])
        let listField = P7SpecField(name: "items", spec: spec, attributes: ["type": "list"])
        let intField = P7SpecField(name: "count", spec: spec, attributes: ["type": "uint32"])

        XCTAssertTrue(stringField.hasExplicitLength())
        XCTAssertTrue(dataField.hasExplicitLength())
        XCTAssertTrue(listField.hasExplicitLength())
        XCTAssertFalse(intField.hasExplicitLength())
    }

    func testSpecItemDescriptionUsesSafeFallbacksWhenIDMissing() {
        let spec = P7Spec(withPath: nil)
        let noID = P7SpecItem(name: "wired.custom", spec: spec, attributes: [:])
        XCTAssertEqual(noID.description, "[?] wired.custom")

        let withID = P7SpecItem(name: "wired.okay", spec: spec, attributes: ["id": "1000"])
        XCTAssertEqual(withID.description, "[1000] wired.okay")
    }
}
