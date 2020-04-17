//
//  WiredSwfitTests.swift
//  WiredSwfitTests
//
//  Created by Rafael Warnault on 28/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import XCTest
import WiredSwfit

class WiredSwfitTests: XCTestCase {

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testUrl() {
        let spec = P7Spec()
        let url = Url(withString: "wired://guest:password@localhost:4871")
        
        XCTAssert(url.scheme == "wired")
        XCTAssert(url.login == "guest")
        XCTAssert(url.password == "password")
        XCTAssert(url.hostname == "localhost")
        XCTAssert(url.port == 4871)
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
            testUrl()
        }
    }

}
