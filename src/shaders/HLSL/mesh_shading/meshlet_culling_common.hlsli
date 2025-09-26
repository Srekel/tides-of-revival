#ifndef _MESHLET_CULLING_COMMON_HLSLI_
#define _MESHLET_CULLING_COMMON_HLSLI_

#include "../../FSL/d3d.h"
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

bool FrustumCull(float3 aabb_center, float3 aabb_extents, float4x4 world, float4x4 view_proj)
{
    bool is_visible = true;

    float3 ext = aabb_extents * 2.0f;
    float4x4 extents_basis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(mul(extents_basis, world), view_proj);

    float4 corner_000 = mul(mul(float4(aabb_center - aabb_extents, 1), world), view_proj);
    float4 corner_100 = corner_000 + axis[0];
    float4 corner_010 = corner_000 + axis[1];
    float4 corner_110 = corner_010 + axis[0];
    float4 corner_001 = corner_000 + axis[2];
    float4 corner_101 = corner_100 + axis[2];
    float4 corner_011 = corner_010 + axis[2];
    float4 corner_111 = corner_110 + axis[2];

    float min_w = min(corner_000.w, corner_001.w);
    min_w = min(min_w, corner_010.w);
    min_w = min(min_w, corner_011.w);
    min_w = min(min_w, corner_100.w);
    min_w = min(min_w, corner_101.w);
    min_w = min(min_w, corner_110.w);
    min_w = min(min_w, corner_111.w);

    float max_w = max(corner_000.w, corner_001.w);
    max_w = max(max_w, corner_010.w);
    max_w = max(max_w, corner_011.w);
    max_w = max(max_w, corner_100.w);
    max_w = max(max_w, corner_101.w);
    max_w = max(max_w, corner_110.w);
    max_w = max(max_w, corner_111.w);

    // Plane inequalities
    float4 plane_mins = min(float4(corner_000.xy, -corner_000.xy) - corner_000.w, float4(corner_001.xy, -corner_001.xy) - corner_001.w);
    plane_mins = min(plane_mins, float4(corner_010.xy, -corner_010.xy) - corner_010.w);
    plane_mins = min(plane_mins, float4(corner_100.xy, -corner_100.xy) - corner_100.w);
    plane_mins = min(plane_mins, float4(corner_110.xy, -corner_110.xy) - corner_110.w);
    plane_mins = min(plane_mins, float4(corner_011.xy, -corner_011.xy) - corner_011.w);
    plane_mins = min(plane_mins, float4(corner_101.xy, -corner_101.xy) - corner_101.w);
    plane_mins = min(plane_mins, float4(corner_111.xy, -corner_111.xy) - corner_111.w);
    plane_mins = min(plane_mins, float4(1, 1, 1, 1));

    // Clip-space AABB
    float3 corner_000_cs = corner_000.xyz / corner_000.w;
    float3 corner_100_cs = corner_100.xyz / corner_100.w;
    float3 corner_010_cs = corner_010.xyz / corner_010.w;
    float3 corner_110_cs = corner_110.xyz / corner_110.w;
    float3 corner_001_cs = corner_001.xyz / corner_001.w;
    float3 corner_101_cs = corner_101.xyz / corner_101.w;
    float3 corner_011_cs = corner_011.xyz / corner_011.w;
    float3 corner_111_cs = corner_111.xyz / corner_111.w;

    float3 rect_min = min(corner_000_cs, corner_100_cs);
    rect_min = min(rect_min, corner_010_cs);
    rect_min = min(rect_min, corner_110_cs);
    rect_min = min(rect_min, corner_001_cs);
    rect_min = min(rect_min, corner_101_cs);
    rect_min = min(rect_min, corner_011_cs);
    rect_min = min(rect_min, corner_111_cs);
    rect_min = min(rect_min, float3(1, 1, 1));

    float3 rect_max = max(corner_000_cs, corner_100_cs);
    rect_max = max(rect_max, corner_010_cs);
    rect_max = max(rect_max, corner_110_cs);
    rect_max = max(rect_max, corner_001_cs);
    rect_max = max(rect_max, corner_101_cs);
    rect_max = max(rect_max, corner_011_cs);
    rect_max = max(rect_max, corner_111_cs);
    rect_max = max(rect_max, float3(-1, -1, -1));

    is_visible &= rect_max.z > 0;

    if (min_w <= 0 && max_w > 0)
    {
        rect_min = -1;
        rect_max = 1;
        is_visible = true;
    }
    else
    {
        is_visible &= max_w > 0.0f;
    }

    is_visible &= !any(plane_mins > 0.0f);

    return is_visible;
}

#endif // _MESHLET_CULLING_COMMON_HLSLI_