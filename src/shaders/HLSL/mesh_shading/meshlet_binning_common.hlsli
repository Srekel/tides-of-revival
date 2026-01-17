#ifndef _MESHLET_BINNING_COMMON_HLSLI_
#define _MESHLET_BINNING_COMMON_HLSLI_

#include "meshlet_culling_common.hlsli"

struct BinningParams
{
    uint binsCount;
    uint meshletCountsBufferIndex;
    uint meshletOffsetAndCountsBufferIndex;
    uint globalMeshletCounterBufferIndex;
    uint binnedMeshletsBufferIndex;
    uint dispatchArgsBufferIndex;
    uint visibleMeshletsBufferIndex;
    uint visibleMeshletsCountersBufferIndex;
};

cbuffer g_BinningParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    BinningParams g_BinningParams;
};

uint GetMeshletsCount()
{
    ByteAddressBuffer visibleMeshletsCountersBuffer = ResourceDescriptorHeap[g_BinningParams.visibleMeshletsCountersBufferIndex];
    return visibleMeshletsCountersBuffer.Load<uint>(COUNTER_PHASE1_VISIBLE_MESHLETS);
}

uint GetBin(uint meshletIndex)
{
    ByteAddressBuffer visibleMeshletBuffer = ResourceDescriptorHeap[g_BinningParams.visibleMeshletsBufferIndex];
    MeshletCandidate candidate = visibleMeshletBuffer.Load<MeshletCandidate>(meshletIndex * sizeof(MeshletCandidate));
    MaterialData material = getMaterial(candidate.materialIndex);
    return material.rasterizerBin;
}

#endif // _MESHLET_BINNING_COMMON_HLSLI_