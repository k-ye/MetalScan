//
//  ExclusiveScanTests.swift
//  MetalScanAppTests
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import XCTest
@testable import MetalScanApp

fileprivate let kThreadsPerGroupCount = 512

fileprivate protocol DataGenerator {
    func genPoint() -> Int32
}

extension DataGenerator {
    func genData(count: Int) -> [Int32] {
        var result = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = genPoint()
        }
        return result
    }
}

class ExclusiveScanTests: XCTestCase {
    private class RandomDataGen : DataGenerator {
        private let max: Int32
        
        init(max: Int32) {
            self.max = max
        }
        func genPoint() -> Int32 { return Int32.random(in: 0..<max) }
    }
    private class OnlyOneGen : DataGenerator {
        // Easier for debugging
        func genPoint() -> Int32 { return 1 }
    }
    
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var es: ExclusiveScan!
    private var dataGen: DataGenerator!

    override func setUp() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        es = ExclusiveScan.makeDynamicCount(device)
        dataGen = RandomDataGen(max: 1000)
    }

    func testBasic() {
        let data: [Int32] = [1, 2, 3, 4, 5]
        runTestScan(data)
    }
    
    func testSingleGroup() {
        let data = dataGen.genData(count: kThreadsPerGroupCount)
        runTestScan(data)
    }
    
    func testSingleGroup_NotPowerOfTwo() {
        let data = dataGen.genData(count: 233)
        runTestScan(data)
    }
    
    func testTwoTiers() {
        let data = dataGen.genData(count: kThreadsPerGroupCount * 128)
        runTestScan(data)
    }
    
    func testTwoTiers_NotPowerOfTwo() {
        let data = dataGen.genData(count: kThreadsPerGroupCount * 128 + 233)
        runTestScan(data)
    }
    
    
    func testTwoTiers_DisableBlockSumBuffers() {
        for i in 10...50 {
            let data = dataGen.genData(count: kThreadsPerGroupCount * i + 233)
            runTestScan(data)
        }
    }
    
    func testTwoTiers_EnableBlockSumBuffers() {
        let count = kThreadsPerGroupCount * 10 + 233
        es = ExclusiveScan.makeStaticCount(inputCount: count, device)
        // Run this multiple times to make sure the blockSumBuffers do not need
        // reset every time we run the scan
        for _ in 0..<50 {
            let data = dataGen.genData(count: count)
            runTestScan(data)
        }
    }
    
    func testThreeTiers() {
        // Reduce the upper range, otherwise it may overflow
        dataGen = RandomDataGen(max: 10)
        let data = dataGen.genData(count: kThreadsPerGroupCount * kThreadsPerGroupCount * 4)
        runTestScan(data)
    }
    
    func testThreeTiers_EnableBlockSumBuffers() {
        dataGen = RandomDataGen(max: 10)
        let count = kThreadsPerGroupCount * kThreadsPerGroupCount + 233
        es = ExclusiveScan.makeStaticCount(inputCount: count, device)
        // Run this multiple times to make sure the blockSumBuffers do not need
        // reset every time we run the scan
        for _ in 0..<5 {
            let data = dataGen.genData(count: count)
            runTestScan(data)
        }
    }
    
    func testScan_DisableBlockSumBuffers_BM() {
        dataGen = RandomDataGen(max: 10)
        let count = 500_000
        self.measure {
            let data = dataGen.genData(count: count)
            let _ = es.scan(data: data, commandQueue)
        }
    }
    
    func testScan_EnableBlockSumBuffers_BM() {
        dataGen = RandomDataGen(max: 10)
        let count = 500_000
        es = ExclusiveScan.makeStaticCount(inputCount: count, device)
        self.measure {
            let data = dataGen.genData(count: count)
            let _ = es.scan(data: data, commandQueue)
        }
    }
    
    private func runTestScan(_ data: [Int32]) {
        let validator = ScanIterator(data)
        let scanResult = es.scan(data: data, commandQueue)
        for (i, actual) in scanResult.enumerated() {
            let expected = validator.next()
            XCTAssertEqual(actual, expected,
                           "i=\(i) expected=\(expected) actual=\(actual)")
        }
        XCTAssertTrue(validator.done)
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
