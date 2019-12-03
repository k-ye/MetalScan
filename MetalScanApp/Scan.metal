//
//  Scan.metal
//  MetalScanApp
//
//  Created by Ye Kuang on 10/25/19.
//  Copyright © 2019 yekuang. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

struct Constants {
    uint count;
};

kernel void exclusive_scan(device const int32_t* input_data [[buffer(0)]],
                           device int32_t* output_data [[buffer(1)]],
                           device int32_t* block_sum [[buffer(2)]],
                           constant const Constants& c [[buffer(3)]],
                           threadgroup int32_t* tg_mem [[threadgroup(0)]],
                           uint tid [[thread_position_in_grid]],
                           uint tgid [[thread_position_in_threadgroup]],
                           uint gid [[threadgroup_position_in_grid]],
                           const uint threads_per_group [[threads_per_threadgroup]]) {
    // https://developer.nvidia.com/gpugems/GPUGems3/gpugems3_ch39.html
    const uint count = c.count;
    if (tid < count) {
        tg_mem[tgid] = input_data[tid];
    } else {
        tg_mem[tgid] = 0;
    }
    // https://stackoverflow.com/questions/44660599/metal-mem-none-vs-mem-threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // up-sweep
    uint stride = 2;
    while (stride <= threads_per_group) {
        threadgroup_barrier(mem_flags::mem_threadgroup);
        const uint half_stride = (stride >> 1);
        if (((tgid + 1) % stride) == 0) {
            tg_mem[tgid] += tg_mem[tgid - half_stride];
        }
        stride <<= 1;
    }
    
    // Without this barrier, setting tg_mem[-1] to 0 may not be properly
    // propagated across the entire threadgroup.
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tgid == 0) {
        // clear the last element
        block_sum[gid] = tg_mem[threads_per_group - 1];
        tg_mem[threads_per_group - 1] = 0;
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
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid < count) {
         output_data[tid] = tg_mem[tgid];
    }
}

kernel void add_block_sum(device const int32_t* block_sum [[buffer(0)]],
                          device int32_t* data [[buffer(1)]],
                          constant const Constants& c[[buffer(2)]],
                          uint tid [[thread_position_in_grid]],
                          uint gid [[threadgroup_position_in_grid]]) {
    if (tid < c.count) {
        data[tid] += block_sum[gid];
    }
}
