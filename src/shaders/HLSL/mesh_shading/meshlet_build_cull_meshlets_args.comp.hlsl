#include "meshlet_culling_common.hlsli"

struct MeshletsCullArgsParams
{
    uint candidateMeshletsCountersBufferIndex;
    uint dispatchArgsBufferInex;
};

cbuffer g_MeshletsCullArgsParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    MeshletsCullArgsParams g_MeshletsCullArgsParams;
};

[numthreads(1, 1, 1)] void main()
{
    ByteAddressBuffer candidateMeshletsCountersBuffer = ResourceDescriptorHeap[g_MeshletsCullArgsParams.candidateMeshletsCountersBufferIndex];
    RWByteAddressBuffer argumentsBuffer = ResourceDescriptorHeap[g_MeshletsCullArgsParams.dispatchArgsBufferInex];
    uint meshletsCount = candidateMeshletsCountersBuffer.Load<uint>(COUNTER_PHASE1_CANDIDATE_MESHLETS * sizeof(uint));
    uint3 args = uint3(1, 1, 1);
    args.x = (meshletsCount + CULL_MESHLETS_THREADS_COUNT - 1) / CULL_MESHLETS_THREADS_COUNT;
    argumentsBuffer.Store<uint3>(0 * sizeof(uint3), args);
}