#include "../../FSL/d3d.h"
#include "types.hlsli"

struct DestroyParams
{
    uint instancesBufferIndex;
    uint instancesToDestroyBufferIndex;
    uint instancesToDestroyCount;
    uint _padding;
};

struct InstanceToDestroy
{
    uint index;
};

cbuffer g_DestroyParams : register(b0, UPDATE_FREQ_PER_FRAME)
{
    DestroyParams g_DestroyParams;
};

[numthreads(1, 1, 1)] void main()
{
    RWByteAddressBuffer instancesBuffer = ResourceDescriptorHeap[g_DestroyParams.instancesBufferIndex];
    ByteAddressBuffer instancesToDestroyBuffer = ResourceDescriptorHeap[g_DestroyParams.instancesToDestroyBufferIndex];

    for (uint i = 0; i < g_DestroyParams.instancesToDestroyCount; i++)
    {
        InstanceToDestroy instanceToDestroy = instancesToDestroyBuffer.Load<InstanceToDestroy>(i * sizeof(InstanceToDestroy));
        uint instanceOffset = instanceToDestroy.index * sizeof(Instance);
        Instance destroyedInstance = (Instance)0;
        destroyedInstance.flags = 1;
        instancesBuffer.Store<Instance>(instanceOffset, destroyedInstance);
    }
}