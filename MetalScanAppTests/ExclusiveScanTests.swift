//
//  ExclusiveScanTests.swift
//  MetalScanAppTests
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import XCTest
import MetalScanApp

fileprivate let kThreadsPerGroupCount = 256

class ExclusiveScanTests: XCTestCase {
    enum GenDataPolicy {
        case Random
        case OnlyOne  // Easier for debugging
    }
    
    var es: ExclusiveScan!
    let policy: GenDataPolicy = .Random

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
        let data = generateData(count: kThreadsPerGroupCount)
        runTestScan(data)
    }
    
    func testSingleGroup_NotPowerOfTwo() {
        let data = generateData(count: 233)
        runTestScan(data)
    }
    
    func testTwoTiers() {
        let data = generateData(count: kThreadsPerGroupCount * 128)
        runTestScan(data)
    }
    
    private func runTestScan(_ data: [Int32]) {
        let validator = ScanIterator(data)
        let scanResult = es.scan(data: data)
        for (i, actual) in scanResult.enumerated() {
            let expected = validator.next()
            XCTAssertEqual(actual, expected,
                           "i=\(i) expected=\(expected) actual=\(actual)")
        }
        XCTAssertTrue(validator.done)
    }
    
    private func generateData(count: Int) -> [Int32] {
        var data = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            var val = Int32(0)
            switch policy {
            case .Random:
                val = Int32.random(in: 0..<10000)
            default:
                val = 1
            }
            data[i] = val
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
