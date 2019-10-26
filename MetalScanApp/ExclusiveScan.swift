//
//  ExclusiveScan.swift
//  MetalScanApp
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import Metal

fileprivate let kThreadsPerGroupCount = 256

public class ExclusiveScan {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var scanPipelineState: MTLComputePipelineState!
    private var addBlockSumPipelineState: MTLComputePipelineState!
    
    private struct Constants {
        var count: uint
    }
    
    public init() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device.makeCommandQueue()
        guard let mtlLib = device.makeDefaultLibrary(),
            let scanKernel = mtlLib.makeFunction(name: "exclusive_scan"),
            let addBlockSumKernel = mtlLib.makeFunction(name: "add_block_sum") else {
            fatalError("Cannot initialize MetalScan")
        }
        scanPipelineState = try! device.makeComputePipelineState(function: scanKernel)
        addBlockSumPipelineState = try! device.makeComputePipelineState(function: addBlockSumKernel)
    }
    
    public func scan(data: [Int32]) -> [Int32] {
        let count = data.count
        guard let dataBuffer = device.makeBuffer(bytes: data,
                                                 length: count * MemoryLayout<Int32>.stride,
                                                 options: [])
            else { fatalError("Cannot scan") }
        
        doScan(dataBuffer, count)
        
        let bound = dataBuffer.contents().bindMemory(to: Int32.self, capacity: count)
        var result = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = bound[i]
        }
        return result
    }
    
    private func doScan(_ dataBuffer: MTLBuffer, _ count: Int) {
        guard let scanCmdBuffer = commandQueue.makeCommandBuffer(),
            let scanEncoder = scanCmdBuffer.makeComputeCommandEncoder() else {
            fatalError("Cannot launch scan kernel")
        }
        let threadsPerGroupMtlSz = MTLSizeMake(kThreadsPerGroupCount, 1, 1)
        let threadgroupsCount = (count + kThreadsPerGroupCount - 1) / kThreadsPerGroupCount
        let threadgroupMtlSz = MTLSize(width: threadgroupsCount, height: 1, depth: 1)
        var constants = Constants(count: uint(count))
        guard let blockSumBuffer = device.makeBuffer(length: threadgroupsCount * MemoryLayout<Int32>.stride,
                                                     options: []) else {
                                                        fatalError("Cannot create blockSumBuffer")
        }
        
        scanEncoder.setComputePipelineState(scanPipelineState)
        scanEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        scanEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 1)
        scanEncoder.setBuffer(blockSumBuffer, offset: 0, index: 2)
        scanEncoder.dispatchThreadgroups(threadgroupMtlSz, threadsPerThreadgroup: threadsPerGroupMtlSz)
        scanEncoder.endEncoding()
        
        scanCmdBuffer.commit()
        scanCmdBuffer.waitUntilCompleted()
        
        if threadgroupsCount <= 1 {
            return
        }
        
        doScan(blockSumBuffer, threadgroupsCount)
        guard let addBlockSumCmdBuffer = commandQueue.makeCommandBuffer(),
            let addBlockSumEncoder = addBlockSumCmdBuffer.makeComputeCommandEncoder() else {
            fatalError("Cannot launch add_block_sum kernel")
        }
        addBlockSumEncoder.setComputePipelineState(addBlockSumPipelineState)
        addBlockSumEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        addBlockSumEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 1)
        addBlockSumEncoder.setBuffer(blockSumBuffer, offset: 0, index: 2)
        addBlockSumEncoder.dispatchThreadgroups(threadgroupMtlSz, threadsPerThreadgroup: threadsPerGroupMtlSz)
        addBlockSumEncoder.endEncoding()
        
        addBlockSumCmdBuffer.commit()
        addBlockSumCmdBuffer.waitUntilCompleted()
    }
}
