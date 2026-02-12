#include "../FSL/d3d.h"
#include "types.hlsli"
#include "debug_line_rendering.hlsli"

struct LightCullParams
{
    float4x4 viewProj;
    uint lightsCount;
    uint lightsBufferIndex;
    uint visibleLightsCountBufferIndex;
    uint visibleLightsBufferIndex;
    float3 cameraPosition;
    float maxDistance;
};

cbuffer g_Params : register(b0, UPDATE_FREQ_PER_FRAME)
{
    LightCullParams g_Params;
}

[numthreads(1, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    RWByteAddressBuffer outputLightsCountBuffer = ResourceDescriptorHeap[g_Params.visibleLightsCountBufferIndex];
    outputLightsCountBuffer.Store<uint>(0, 0);

    float4x4 translation = {
        1, 0, 0, 100,
        0, 1, 0, 100,
        0, 0, 1, 100,
        0, 0, 0, 1};
    float3 localCenter = float3(0, 0, 0);
    float3 localExtents = float3(1, 1, 1);
    DrawBoundingSphere(localCenter, localExtents, translation);
}