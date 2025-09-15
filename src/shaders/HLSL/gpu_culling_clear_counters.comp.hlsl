#include "gpu_culling_resources.hlsli"

[numthreads(1, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    RWByteAddressBuffer countersBuffer = ResourceDescriptorHeap[g_CountersBufferIndex];
    for (uint i = 0; i < g_CountersBufferCount; i++)
    {
        countersBuffer.Store<uint>(i * sizeof(uint), 0);
    }
}