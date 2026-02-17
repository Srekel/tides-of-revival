#include "../FSL/d3d.h"
#include "types.hlsli"
#include "math.hlsli"

#define TILED_CULLING_BLOCKSIZE 16

struct ComputeShaderInput
{
    uint3 groupID : SV_GroupID;                   // 3D index of the thread group in the dispatch
    uint3 groupThreadID : SV_GroupThreadID;       // 3D index of the local thread ID in a thread group
    uint3 dispatchThreadID : SV_DispatchThreadID; // 3D index of the global thread ID in the dispatch
    uint groupIndex : SV_GroupIndex;              // Flattened local index of the thread within a thread group
};

struct DispatchParams
{
    float4x4 view;
    float4x4 projInv;
    float2 ScreenDimensions;
    float2 _pad0;
    uint3 numThreadGroups; // Number of groups dispatched.
    uint lightsCount;
    uint3 numThreads;
    uint _pad1;
};

cbuffer g_DispatchParams : register(b0, UPDATE_FREQ_PER_FRAME)
{
    DispatchParams g_DispatchParams;
}

Texture2D g_DepthBuffer : register(t0, UPDATE_FREQ_NONE);

// Global counter for current index into the light index list
StructuredBuffer<GpuLight> g_Lights : register(t0, UPDATE_FREQ_PER_FRAME);
RWStructuredBuffer<uint> g_LightIndexCounter : register(u0, UPDATE_FREQ_PER_FRAME);
RWStructuredBuffer<uint> g_LightIndexList : register(u1, UPDATE_FREQ_PER_FRAME);
RWTexture2D<uint2> g_LightGrid : register(u2, UPDATE_FREQ_PER_FRAME);

// NOTE: HLSL 6.8 doesn't provide an atomic add for floats yet
groupshared uint uMinDepth;
groupshared uint uMaxDepth;
groupshared uint LightCount;
groupshared uint LightIndexStartOffset;
groupshared uint LightList[1024];

void AppendLight(uint lightIndex)
{
    uint index;
    InterlockedAdd(LightCount, 1, index);
    if (index < 1024)
    {
        LightList[index] = lightIndex;
    }
}

// Convert clip space coordinates to view space
float4 ClipToView(float4 clip)
{
    // View space position
    float4 view = mul(g_DispatchParams.projInv, clip);
    // Perspective projection
    view = view / view.w;

    return view;
}

// Convert screen space coordinates to view space
float4 ScreenToView(float4 screen)
{
    // Convert to normalized texture coordinates
    float2 texCoord = screen.xy / g_DispatchParams.ScreenDimensions;
    // Convert to clip space
    float4 clip = float4(float2(texCoord.x, 1.0f - texCoord.y) * 2.0f - 1.0f, screen.z, screen.w);

    return ClipToView(clip);
}

[numthreads(TILED_CULLING_BLOCKSIZE, TILED_CULLING_BLOCKSIZE, 1)] void main(ComputeShaderInput input)
{
    if (input.dispatchThreadID.x >= uint(g_DispatchParams.ScreenDimensions.x) || input.dispatchThreadID.y >= uint(g_DispatchParams.ScreenDimensions.y))
    {
        return;
    }

    // Calculate min & max depth in threadgroup / tile
    int2 texCoord = input.dispatchThreadID.xy;
    float fDepth = g_DepthBuffer.Load(int3(texCoord, 0)).r;
    uint uDepth = asuint(fDepth);

    // Avoid contention by other threads in the dgroup
    if (input.groupIndex == 0)
    {
        uMinDepth = 0xffffffff;
        uMaxDepth = 0;
        LightCount = 0;
    }

    GroupMemoryBarrierWithGroupSync();

    InterlockedMin(uMinDepth, uDepth);
    InterlockedMin(uMaxDepth, uDepth);

    GroupMemoryBarrierWithGroupSync();

    // NOTE: Swapping min/max because of reverse depth buffer
    float fMinDepth = asfloat(uMaxDepth);
    float fMaxDepth = asfloat(uMinDepth);
    fMaxDepth = max(0.000001, fMaxDepth);

    Frustum GroupFrustum;
    // View space frustum corners:
    uint3 Gid = input.groupID;
    float3 viewSpace[8];
    // Top left point, near
    viewSpace[0] = ScreenToView(float4(Gid.xy * TILED_CULLING_BLOCKSIZE, fMinDepth, 1.0f)).xyz;
    // Top right point, near
    viewSpace[1] = ScreenToView(float4(float2(Gid.x + 1, Gid.y) * TILED_CULLING_BLOCKSIZE, fMinDepth, 1.0f)).xyz;
    // Bottom left point, near
    viewSpace[2] = ScreenToView(float4(float2(Gid.x, Gid.y + 1) * TILED_CULLING_BLOCKSIZE, fMinDepth, 1.0f)).xyz;
    // Bottom right point, near
    viewSpace[3] = ScreenToView(float4(float2(Gid.x + 1, Gid.y + 1) * TILED_CULLING_BLOCKSIZE, fMinDepth, 1.0f)).xyz;
    // Top left point, far
    viewSpace[4] = ScreenToView(float4(Gid.xy * TILED_CULLING_BLOCKSIZE, fMaxDepth, 1.0f)).xyz;
    // Top right point, far
    viewSpace[5] = ScreenToView(float4(float2(Gid.x + 1, Gid.y) * TILED_CULLING_BLOCKSIZE, fMaxDepth, 1.0f)).xyz;
    // Bottom left point, far
    viewSpace[6] = ScreenToView(float4(float2(Gid.x, Gid.y + 1) * TILED_CULLING_BLOCKSIZE, fMaxDepth, 1.0f)).xyz;
    // Bottom right point, far
    viewSpace[7] = ScreenToView(float4(float2(Gid.x + 1, Gid.y + 1) * TILED_CULLING_BLOCKSIZE, fMaxDepth, 1.0f)).xyz;

    // Left plane
    GroupFrustum.planes[0] = ComputePlane(viewSpace[2], viewSpace[0], viewSpace[4]);
    // Right plane
    GroupFrustum.planes[1] = ComputePlane(viewSpace[1], viewSpace[3], viewSpace[5]);
    // Top plane
    GroupFrustum.planes[2] = ComputePlane(viewSpace[0], viewSpace[1], viewSpace[4]);
    // Bottom plane
    GroupFrustum.planes[3] = ComputePlane(viewSpace[3], viewSpace[2], viewSpace[6]);

    // TODO(pixeljuice): Verify that this works with a left-handed coordinate system
    // Convert depth values to view space
    float minDepthVS = ScreenToView(float4(0, 0, fMinDepth, 1)).z;
    float maxDepthVS = ScreenToView(float4(0, 0, fMaxDepth, 1)).z;
    float nearClipVS = ScreenToView(float4(0, 0, 1, 1)).z;

    // Clipping plane for minimum depth value
    Plane minPlane = {float3(0, 0, -1), -minDepthVS};

    for (uint i = input.groupIndex; i < g_DispatchParams.lightsCount; i += TILED_CULLING_BLOCKSIZE * TILED_CULLING_BLOCKSIZE)
    {
        GpuLight light = g_Lights[i];
        if (light.light_type == 0)
        {
            AppendLight(i);
        }
        else if (light.light_type == 1)
        {
            float3 positionVS = mul(g_DispatchParams.view, float4(light.position.xyz, 1)).xyz;
            Sphere sphere = {positionVS.xyz, light.radius * light.radius};
            if (SphereInsideFrustum(sphere, GroupFrustum, nearClipVS, maxDepthVS))
            {
                if (!SphereInsidePlane(sphere, minPlane))
                {
                    AppendLight(i);
                }
            }
        }
    }

    GroupMemoryBarrierWithGroupSync();

    // Update global memory with visible light buffer.
    // First update the light grid (only thread 0 in group needs to do this)
    if (input.groupIndex == 0)
    {
        // Update light grid
        InterlockedAdd(g_LightIndexCounter[0], LightCount, LightIndexStartOffset);
        g_LightGrid[input.groupID.xy] = uint2(LightIndexStartOffset, LightCount);
    }

    GroupMemoryBarrierWithGroupSync();

    // Update the light index list
    for (uint i = input.groupIndex; i < LightCount; i += TILED_CULLING_BLOCKSIZE * TILED_CULLING_BLOCKSIZE)
    {
        g_LightIndexList[LightIndexStartOffset + i] = LightList[i];
    }
}