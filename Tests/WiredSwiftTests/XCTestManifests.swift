import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(ConfigFileDefaultsTests.allTests),
        testCase(WiredSwiftTests.allTests),
    ]
}
#endif
