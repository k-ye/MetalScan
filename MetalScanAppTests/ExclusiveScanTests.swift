//
//  ExclusiveScanTests.swift
//  MetalScanAppTests
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import XCTest
import MetalScanApp

class ExclusiveScanTests: XCTestCase {
    var es: ExclusiveScan!

    override func setUp() {
        es = ExclusiveScan()
    }

    override func tearDown() {
    }

    func testBasic() {
        let data: [Int32] = [1, 2, 3, 4]
        let result = es.scan(data: data)
        print("output=\(result)")
    }

}
