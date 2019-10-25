//
//  ExclusiveScan.swift
//  MetalScanApp
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import Metal

fileprivate let threadgroupSize = 256

public class ExclusiveScan {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLComputePipelineState!
    
    private struct Constants {
        var count: uint
    }
    
    public init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        guard let defaultLib = device.makeDefaultLibrary(),
            let kernelFunc = defaultLib.makeFunction(name: "exclusive_scan") else {
            fatalError("Cannot initialize MetalScan")
        }
        pipelineState = try! device.makeComputePipelineState(function: kernelFunc)
    }
    
    public func scan(data: [Int32]) -> [Int32] {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()
            else { fatalError("Cannot scan") }
        
        let count = data.count
        let threadsPerGroup = MTLSizeMake(threadgroupSize, 1, 1)
        let numThreadgroups = (count + threadgroupSize - 1) / threadgroupSize
        let threadgroupCount = MTLSize(width: numThreadgroups, height: 1, depth: 1)
        let dataBuffer = device.makeBuffer(bytes: data,
                                           length: count * MemoryLayout<Int32>.stride,
                                           options: [])
        var constants = Constants(count: uint(count))
        let blockSumBuffer = device.makeBuffer(length: numThreadgroups * MemoryLayout<Int32>.stride,
                                               options: [])
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        commandEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 1)
        commandEncoder.setBuffer(blockSumBuffer, offset: 0, index: 2)
        commandEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerGroup)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let bound = dataBuffer?.contents().bindMemory(to: Int32.self, capacity: count)
        var result = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = bound![i]
        }
        return result
    }
}
