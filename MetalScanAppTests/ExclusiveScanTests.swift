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
        runTestScan(data)
    }
    
    func testSingleGroup() {
        let data = generateData(count: 256)
        runTestScan(data)
    }
    
    func testSingleGroup_NotPowerOfTwo() {
        let data = generateData(count: 233)
        runTestScan(data)
    }
    
    func testTwoTiers() {
        let data = generateData(count: 256 * 5)
        runTestScan(data)
    }
    
    private func runTestScan(_ data: [Int32]) {
        let validator = ScanIterator(data)
        let scanResult = es.scan(data: data)
        for n in scanResult {
            XCTAssertEqual(n, validator.next())
        }
        XCTAssertTrue(validator.done)
    }
    
    private func generateData(count: Int) -> [Int32] {
        var data = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            data[i] = Int32.random(in: 0..<1000)
        }
        return data
    }
    
    private class ScanIterator {
        private var data: [Int32]
        private var val: Int32
        private var cursor: Int
        
        init(_ data: [Int32]) {
            self.data = data
            val = 0
            cursor = 0
        }
        
        func next() -> Int32 {
            guard !done else { fatalError("Exhausted") }
            let result = val
            val += data[cursor]
            cursor += 1
            return result
        }
        
        var done: Bool {
            get { return cursor >= data.count }
        }
    }
}
