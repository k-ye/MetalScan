//
//  ExclusiveScan.swift
//  MetalScanApp
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import Metal

fileprivate let kThreadsPerGroupCount = 512

fileprivate class BlockSumBuffersProvider {
    let isDynamic: Bool
    private var _inputCount: Int = .zero
    private var buffers = [MTLBuffer]()
    
    var inputCount: Int { get { return _inputCount } }
    
    init() {
        isDynamic = true
    }
    
    init(inputCount: Int, _ device: MTLDevice) {
        isDynamic = false
        self._inputCount = inputCount
        buildBuffers(device)
    }
    
    func matches(inputCount count: Int) -> Bool {
        return count == _inputCount
    }
    
    func set(inputCount: Int, _ device: MTLDevice) {
        if !isDynamic {
            fatalError("isDynamic=\(isDynamic)")
        }
        if inputCount == self._inputCount {
            return
        }
        
        self._inputCount = inputCount
        buildBuffers(device)
    }

    
    func getBuffer(at level: Int) -> MTLBuffer {
        return buffers[level]
    }
    
    private func buildBuffers(_ device: MTLDevice) {
        buffers.removeAll()
        var c = _inputCount
        let s = MemoryLayout<Int32>.stride
        while true {
            c = (c + kThreadsPerGroupCount - 1) / kThreadsPerGroupCount
            buffers.append(device.makeBuffer(length: c * s, options: [])!)
            if c <= 1 {
                break
            }
        }
    }
}

public class ExclusiveScan {
    private var bsbp: BlockSumBuffersProvider!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var scanPipelineState: MTLComputePipelineState!
    private var addBlockSumPipelineState: MTLComputePipelineState!
    
    private struct Constants {
        var count: uint
    }
    
    public init(inputCount: Int, _ device: MTLDevice, _ commandQueue: MTLCommandQueue) {
        bsbp = BlockSumBuffersProvider(inputCount: inputCount, device)
        initCommon(device, commandQueue)
    }
    
    public init(_ device: MTLDevice, _ commandQueue: MTLCommandQueue) {
        bsbp = BlockSumBuffersProvider()
        initCommon(device, commandQueue)
    }
    
    private func initCommon(_ device: MTLDevice, _ commandQueue: MTLCommandQueue) {
        self.device = device
        self.commandQueue = commandQueue
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
        if bsbp.isDynamic {
            bsbp.set(inputCount: count, device)
        } else if !bsbp.matches(inputCount: count) {
            fatalError("Size mismatch, expected=\(bsbp.inputCount), actual=\(count)")
        }
        guard let dataBuffer = device.makeBuffer(bytes: data,
                                                 length: count * MemoryLayout<Int32>.stride,
                                                 options: [])
            else { fatalError("Cannot scan") }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Cannot create command buffer")
        }
        doScan(commandBuffer, dataBuffer, count, level: 0)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return toArray(dataBuffer, count)
    }
    
    private func doScan(_ commandBuffer: MTLCommandBuffer, _ dataBuffer: MTLBuffer, _ count: Int, level: Int) {
        guard let scanEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Cannot launch scan kernel")
        }
        let threadsPerGroupMtlSz = MTLSizeMake(kThreadsPerGroupCount, 1, 1)
        let threadgroupsCount = (count + kThreadsPerGroupCount - 1) / kThreadsPerGroupCount
        let threadgroupMtlSz = MTLSize(width: threadgroupsCount, height: 1, depth: 1)
        var constants = Constants(count: uint(count))
        let blockSumBuffer = bsbp.getBuffer(at: level)
        scanEncoder.setComputePipelineState(scanPipelineState)
        scanEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        scanEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 1)
        scanEncoder.setBuffer(blockSumBuffer, offset: 0, index: 2)
        // https://stackoverflow.com/questions/43864136/metal-optimizing-memory-access
        scanEncoder.setThreadgroupMemoryLength(MemoryLayout<Int32>.stride * kThreadsPerGroupCount, index: 0)
        scanEncoder.dispatchThreadgroups(threadgroupMtlSz, threadsPerThreadgroup: threadsPerGroupMtlSz)
        scanEncoder.endEncoding()
        
        if threadgroupsCount <= 1 {
            return
        }
        
        doScan(commandBuffer, blockSumBuffer, threadgroupsCount, level: level + 1)
        guard let addBlockSumEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Cannot launch add_block_sum kernel")
        }
        addBlockSumEncoder.setComputePipelineState(addBlockSumPipelineState)
        addBlockSumEncoder.setBuffer(dataBuffer, offset: 0, index: 0)
        addBlockSumEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 1)
        addBlockSumEncoder.setBuffer(blockSumBuffer, offset: 0, index: 2)
        addBlockSumEncoder.dispatchThreadgroups(threadgroupMtlSz, threadsPerThreadgroup: threadsPerGroupMtlSz)
        addBlockSumEncoder.endEncoding()
    }
    
    private func toArray(_ buffer: MTLBuffer, _ count: Int) -> [Int32] {
        let bound = buffer.contents().bindMemory(to: Int32.self, capacity: count)
        var result = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = bound[i]
        }
        return result
    }
}
