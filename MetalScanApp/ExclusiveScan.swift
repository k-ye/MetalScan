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
    private let bsbp: BlockSumBuffersProvider
    private var _device: MTLDevice!
    public var device: MTLDevice { get { return _device } }
    private var scanPipelineState: MTLComputePipelineState!
    private var addBlockSumPipelineState: MTLComputePipelineState!
    
    public typealias DataType = Int32
    public static let kDataStride = MemoryLayout<DataType>.stride
    
    private struct Constants {
        var count: uint
    }
    
    public static func makeDynamicCount(_ device: MTLDevice) -> ExclusiveScan {
        return ExclusiveScan(device)
    }
    
    public static func makeStaticCount(inputCount: Int, _ device: MTLDevice) -> ExclusiveScan {
        return ExclusiveScan(inputCount: inputCount, device)
    }
    
    private init(_ device: MTLDevice) {
        bsbp = BlockSumBuffersProvider()
        initCommon(device)
    }
    
    private init(inputCount: Int, _ device: MTLDevice) {
        bsbp = BlockSumBuffersProvider(inputCount: inputCount, device)
        initCommon(device)
    }
    
    private func initCommon(_ device: MTLDevice) {
        self._device = device
        guard let mtlLib = device.makeDefaultLibrary(),
            let scanKernel = mtlLib.makeFunction(name: "exclusive_scan"),
            let addBlockSumKernel = mtlLib.makeFunction(name: "add_block_sum") else {
            fatalError("Cannot initialize MetalScan")
        }
        scanPipelineState = try! device.makeComputePipelineState(function: scanKernel)
        addBlockSumPipelineState = try! device.makeComputePipelineState(function: addBlockSumKernel)
    }
    
    public func scan(inputBuffer: MTLBuffer, outputBuffer: MTLBuffer, count: Int, _ commandBuffer: MTLCommandBuffer) {
        if bsbp.isDynamic {
            bsbp.set(inputCount: count, _device)
        } else if !bsbp.matches(inputCount: count) {
            fatalError("Size mismatch, expected=\(bsbp.inputCount), actual=\(count)")
        }
        doScan(inputBuffer: inputBuffer, outputBuffer: outputBuffer, count: count, commandBuffer, level: 0)
    }
    
    private func doScan(inputBuffer: MTLBuffer, outputBuffer: MTLBuffer, count: Int,
                        _ commandBuffer: MTLCommandBuffer, level: Int) {
        let scanEncoder = commandBuffer.makeComputeCommandEncoder()!
        let threadgridParams = Mtl1DThreadGridParams.Builder()
            .set(count: count)
            .set(threadsPerGroupCount: kThreadsPerGroupCount)
            .build()

        var constants = Constants(count: uint(count))
        let blockSumBuffer = bsbp.getBuffer(at: level)
        scanEncoder.setComputePipelineState(scanPipelineState)
//        device const int32_t* input_data [[buffer(0)]],
//        device int32_t* output_data [[buffer(1)]],
//        device int32_t* block_sum [[buffer(2)]],
//        constant const Constants& c [[buffer(3)]],
//        threadgroup int32_t* tg_mem [[threadgroup(0)]],
        scanEncoder.setBuffer(inputBuffer, offset: 0, index: 0)
        scanEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        scanEncoder.setBuffer(blockSumBuffer, offset: 0, index: 2)
        scanEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 3)
        // https://stackoverflow.com/questions/43864136/metal-optimizing-memory-access
        scanEncoder.setThreadgroupMemoryLength(MemoryLayout<Int32>.stride * kThreadsPerGroupCount, index: 0)
        threadgridParams.dispatch(scanEncoder)
        scanEncoder.endEncoding()
        
        let threadgroupsCount = threadgridParams.threadgroupsSize.width
        if threadgroupsCount <= 1 {
            return
        }
        
        doScan(inputBuffer: blockSumBuffer, outputBuffer: blockSumBuffer, count: threadgroupsCount,
               commandBuffer, level: level + 1)
        let addBlockSumEncoder = commandBuffer.makeComputeCommandEncoder()!
        addBlockSumEncoder.setComputePipelineState(addBlockSumPipelineState)
//        device const int32_t* block_sum [[buffer(0)]],
//        device int32_t* data [[buffer(1)]],
//        constant const Constants& c[[buffer(2)]],
        addBlockSumEncoder.setBuffer(blockSumBuffer, offset: 0, index: 0)
        addBlockSumEncoder.setBuffer(outputBuffer, offset: 0, index: 1)
        addBlockSumEncoder.setBytes(&constants, length: MemoryLayout<Constants>.stride, index: 2)
        threadgridParams.dispatch(addBlockSumEncoder)
        addBlockSumEncoder.endEncoding()
    }
}
