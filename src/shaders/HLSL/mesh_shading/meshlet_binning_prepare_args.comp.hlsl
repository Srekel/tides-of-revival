#include "meshlet_binning_common.hlsli"

[numthreads(1, 1, 1)] void main()
{
    RWByteAddressBuffer meshletCountsBuffer = ResourceDescriptorHeap[g_BinningParams.meshletCountsBufferIndex];
    for (uint i = 0; i < g_BinningParams.binsCount; i++)
    {
        meshletCountsBuffer.Store<uint>(i * sizeof(uint), 0);
    }

    RWByteAddressBuffer globalMeshletCounterBuffer = ResourceDescriptorHeap[g_BinningParams.globalMeshletCounterBufferIndex];
    globalMeshletCounterBuffer.Store<uint>(0, 0);

    uint meshletsCount = GetMeshletsCount();
    uint3 args = uint3((meshletsCount + 64 - 1) / 64, 1, 1);
    RWByteAddressBuffer dispatchArgsBuffer = ResourceDescriptorHeap[g_BinningParams.dispatchArgsBufferIndex];
    dispatchArgsBuffer.Store<uint3>(0, args);
}