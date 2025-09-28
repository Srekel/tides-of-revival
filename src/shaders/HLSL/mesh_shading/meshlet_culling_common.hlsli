#ifndef _MESHLET_CULLING_COMMON_HLSLI_
#define _MESHLET_CULLING_COMMON_HLSLI_

#include "../../FSL/d3d.h"
#include "../math.hlsli"
#include "defines.hlsli"
#include "types.hlsli"

cbuffer g_Frame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    Frame g_Frame;
}

Instance getInstance(uint instanceIndex)
{
    ByteAddressBuffer instanceBuffer = ResourceDescriptorHeap[g_Frame.instanceBufferIndex];
    Instance instance = instanceBuffer.Load<Instance>(instanceIndex * sizeof(Instance));
    return instance;
}

MaterialData getMaterial(uint materialIndex)
{
    ByteAddressBuffer materialBuffer = ResourceDescriptorHeap[g_Frame.materialBufferIndex];
    MaterialData material = materialBuffer.Load<MaterialData>(materialIndex * sizeof(MaterialData));
    return material;
}

#endif // _MESHLET_CULLING_COMMON_HLSLI_