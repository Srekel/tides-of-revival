#include "../FSL/d3d.h"
#include "types.hlsli"
#include "math.hlsli"
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

[numthreads(32, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x < g_Params.lightsCount)
    {
        ByteAddressBuffer lightsBuffer = ResourceDescriptorHeap[g_Params.lightsBufferIndex];
        RWByteAddressBuffer visibleLightsBuffer = ResourceDescriptorHeap[g_Params.visibleLightsBufferIndex];
        RWByteAddressBuffer visibleLightsCountBuffer = ResourceDescriptorHeap[g_Params.visibleLightsCountBufferIndex];

        GpuLight light = lightsBuffer.Load<GpuLight>(DTid.x * sizeof(GpuLight));

        if (light.light_type == 0)
        {
            uint visibleLightIndex = 0;
            visibleLightsCountBuffer.InterlockedAdd(0, 1, visibleLightIndex);
            visibleLightsBuffer.Store<GpuLight>(visibleLightIndex * sizeof(GpuLight), light);
        }
        else
        {
            float4x4 translation = {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                light.position.x, light.position.y, light.position.z, 1};
            float3 localCenter = float3(0, 0, 0);
            float3 localExtents = float3(light.radius * 0.5, light.radius * 0.5, light.radius * 0.5);
            DrawBoundingSphere(localCenter, localExtents, translation, float4(light.color, 1));
            bool isVisible = FrustumCull(localCenter, localExtents, translation, g_Params.viewProj);

            // float lightDistance = length(light.position - g_Params.cameraPosition);
            // if (lightDistance < g_Params.maxDistance)
            if (isVisible)
            {
                uint visibleLightIndex = 0;
                visibleLightsCountBuffer.InterlockedAdd(0, 1, visibleLightIndex);
                visibleLightsBuffer.Store<GpuLight>(visibleLightIndex * sizeof(GpuLight), light);
            }
        }
    }
}