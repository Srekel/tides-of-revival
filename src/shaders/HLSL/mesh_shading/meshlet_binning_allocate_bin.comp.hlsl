#include "meshlet_binning_common.hlsli"

[numthreads(64, 1, 1)] void main(uint DTid : SV_DispatchThreadID)
{
    RWByteAddressBuffer meshletCountsBuffer = ResourceDescriptorHeap[g_BinningParams.meshletCountsBufferIndex];
    RWByteAddressBuffer globalMeshletCountBuffer = ResourceDescriptorHeap[g_BinningParams.globalMeshletCounterBufferIndex];
    RWByteAddressBuffer meshletOffsetAndCountsBuffer = ResourceDescriptorHeap[g_BinningParams.meshletOffsetAndCountsBufferIndex];

    uint bin = DTid;
    if (bin >= g_BinningParams.binsCount)
        return;

    // Compute the amount of meshlets for each bin and prefix sum to get the global index offset
    uint meshletsCount = meshletCountsBuffer.Load<uint>(bin * sizeof(uint));
    uint offset = WavePrefixSum(meshletsCount);
    uint globalOffset;
    if (WaveIsFirstLane())
        globalMeshletCountBuffer.InterlockedAdd(0, meshletsCount, globalOffset);
    offset += WaveReadLaneFirst(globalOffset);
    meshletOffsetAndCountsBuffer.Store<uint4>(bin * sizeof(uint4), uint4(0, 1, 1, offset));
}