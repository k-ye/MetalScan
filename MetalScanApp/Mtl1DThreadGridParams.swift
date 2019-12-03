//
//  Mtl1DThreadGridParams.swift
//  MetalScanApp
//
//  Created by Ye Kuang on 12/3/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

import Metal

class Mtl1DThreadGridParams {
    class Builder {
        fileprivate var count: Int = .zero
        fileprivate var threadsPerGroupCount: Int = 512
        fileprivate var threadgroupsCount: Int {
            get { return (count + threadsPerGroupCount - 1) / threadsPerGroupCount }
        }
        
        func set(count: Int) -> Builder {
            self.count = count
            return self
        }
        
        func set(threadsPerGroupCount: Int) -> Builder {
            self.threadsPerGroupCount = threadsPerGroupCount
            return self
        }
        
        func build() -> Mtl1DThreadGridParams {
            return Mtl1DThreadGridParams(self)
        }
    }
    
    let count: Int
    let threadsPerGroupSize: MTLSize
    let threadgroupsSize: MTLSize

    private init(_ b: Builder) {
        count = b.count
        threadsPerGroupSize = MTLSizeMake(b.threadsPerGroupCount, 1, 1)
        threadgroupsSize = MTLSizeMake(b.threadgroupsCount, 1, 1)
    }
    
    func dispatch(_ encoder: MTLComputeCommandEncoder) {
        encoder.dispatchThreadgroups(threadgroupsSize, threadsPerThreadgroup: threadsPerGroupSize)
    }
}
