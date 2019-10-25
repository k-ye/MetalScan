//
//  Scan.metal
//  MetalScanApp
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

constant constexpr size_t kThreadgroupSize = 256;

struct Constants {
    uint count;
};

kernel void exclusive_scan(device int32_t* data [[buffer(0)]],
                           constant const Constants& c[[buffer(1)]],
                           device int32_t* block_sum [[buffer(2)]],
                           uint tid [[thread_position_in_grid]],
                           uint tgid [[thread_position_in_threadgroup]],
                           uint gid [[threadgroup_position_in_grid]]) {
    // https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch39.html
    const uint count = c.count;
    threadgroup int32_t tg_mem[kThreadgroupSize];
    if (tid < count) {
        tg_mem[tgid] = data[tid];
    } else {
        tg_mem[tgid] = 0;
    }
    // https://stackoverflow.com/questions/44660599/metal-mem-none-vs-mem-threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tgid == 0) {
        int bs = 0;
        for (int n : tg_mem) {
            bs += n;
        }
        block_sum[gid] = bs;
    }
    
    // up-sweep
    uint stride = 2;
    while (stride <= kThreadgroupSize) {
        threadgroup_barrier(mem_flags::mem_threadgroup);
        const uint half_stride = (stride >> 1);
        if (((tgid + 1) % stride) == 0) {
            tg_mem[tgid] += tg_mem[tgid - half_stride];
        }
        stride <<= 1;
    }
    // clear the last element
    if (tgid == 0) {
        tg_mem[kThreadgroupSize - 1] = 0;
    }
    stride >>= 1;
    
    // down-sweep
    while (stride > 1) {
        threadgroup_barrier(mem_flags::mem_threadgroup);
        const uint half_stride = (stride >> 1);
        if (((tgid + 1) % stride) == 0) {
            const uint prev_idx = tgid - half_stride;
            const int tmp = tg_mem[prev_idx];
            tg_mem[prev_idx] = tg_mem[tgid];
            tg_mem[tgid] += tmp;
        }
        stride = half_stride;
    }
    if (tid < count) {
         data[tid] = tg_mem[tgid];
    }
}
