#ifndef _DEBUG_LINE_RENDERING_HLSLI_
#define _DEBUG_LINE_RENDERING_HLSLI_

#include "../FSL/d3d.h"
#include "math.hlsli"

struct DebugFrame
{
    float4x4 view;
    float4x4 projection;
    float4x4 viewProj;
    float4x4 viewProjInv;

    uint debugLinePointCountMax;
    uint debugLinePointArgsBufferIndex;
    uint debugLineVertexBufferIndex;
    uint _pad1;
};

cbuffer g_DebugFrame : register(b128, UPDATE_FREQ_PER_FRAME)
{
    DebugFrame g_DebugFrame;
}

struct VertexInput
{
    float3 position : POSITION;
    float4 color : COLOR;
};

struct VertexOutput
{
    linear float4 position : SV_POSITION;
    linear float4 color : COLOR;
};

struct DebugLinePoint
{
    float3 position;
    uint color;
};

uint ToUnormRGBA(float4 color)
{
    uint packed = 0;
    packed |= (uint)(color.r * 255.0f);
    packed |= ((uint)(color.g * 255.0f)) << 8;
    packed |= ((uint)(color.b * 255.0f)) << 16;
    packed |= ((uint)(color.a * 255.0f)) << 24;

    return packed;
}

void ClearCounters()
{
    RWByteAddressBuffer lineArgsBuffer = ResourceDescriptorHeap[g_DebugFrame.debugLinePointArgsBufferIndex];
    lineArgsBuffer.Store<uint>(0 * sizeof(uint), 0); // VertexCountPerInstance
    lineArgsBuffer.Store<uint>(1 * sizeof(uint), 1); // Instance Count
    lineArgsBuffer.Store<uint>(2 * sizeof(uint), 0); // StartVertexLocation
    lineArgsBuffer.Store<uint>(3 * sizeof(uint), 0); // StartInstanceLocation
}

void DrawLine(float3 position0, float3 position1, float4 color0, float4 color1)
{
    uint offsetInVertexBuffer;
    RWByteAddressBuffer LineArgsBuffer = ResourceDescriptorHeap[g_DebugFrame.debugLinePointArgsBufferIndex];
    LineArgsBuffer.InterlockedAdd(0 * sizeof(uint), 2, offsetInVertexBuffer);

    RWByteAddressBuffer LineVertexBuffer = ResourceDescriptorHeap[g_DebugFrame.debugLineVertexBufferIndex];

    if (offsetInVertexBuffer < g_DebugFrame.debugLinePointCountMax - 2)
    {
        DebugLinePoint p;
        p.position = position0;
        p.color = ToUnormRGBA(color0);
        LineVertexBuffer.Store<DebugLinePoint>((offsetInVertexBuffer + 0) * sizeof(DebugLinePoint), p);

        p.position = position1;
        p.color = ToUnormRGBA(color1);
        LineVertexBuffer.Store<DebugLinePoint>((offsetInVertexBuffer + 1) * sizeof(DebugLinePoint), p);
    }
}

void DrawLine(float4 position0, float4 position1, float4 color0, float4 color1)
{
    DrawLine(position0.xyz, position1.xyz, color0, color1);
}

void DrawOBB(float3 localBoundsOrigin, float3 localBoundsExtents, float4x4 worldMatrix, float4 color = float4(1, 1, 1, 1))
{
    float3 ext = localBoundsExtents * 2.0f;
    float4x4 extents_basis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(extents_basis, worldMatrix);

    float4 corner_000 = mul(float4(localBoundsOrigin - localBoundsExtents, 1), worldMatrix);
    float4 corner_100 = corner_000 + axis[0];
    float4 corner_010 = corner_000 + axis[1];
    float4 corner_110 = corner_010 + axis[0];
    float4 corner_001 = corner_000 + axis[2];
    float4 corner_101 = corner_100 + axis[2];
    float4 corner_011 = corner_010 + axis[2];
    float4 corner_111 = corner_110 + axis[2];

    // Front quad
    DrawLine(corner_000, corner_100, color, color);
    DrawLine(corner_100, corner_110, color, color);
    DrawLine(corner_110, corner_010, color, color);
    DrawLine(corner_010, corner_000, color, color);
    // Back quad
    DrawLine(corner_001, corner_101, color, color);
    DrawLine(corner_101, corner_111, color, color);
    DrawLine(corner_111, corner_011, color, color);
    DrawLine(corner_011, corner_001, color, color);
    // Bottom/Top Connections
    DrawLine(corner_000, corner_001, color, color);
    DrawLine(corner_100, corner_101, color, color);
    DrawLine(corner_010, corner_011, color, color);
    DrawLine(corner_110, corner_111, color, color);
}

void DrawAABB(float3 localBoundsOrigin, float3 localBoundsExtents, float4x4 worldMatrix, float4 color = float4(1, 1, 1, 1))
{
    float3 ext = localBoundsExtents * 2.0f;
    float4x4 extents_basis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(extents_basis, worldMatrix);

    float4 corner_000 = mul(float4(localBoundsOrigin - localBoundsExtents, 1), worldMatrix);
    float4 corner_100 = corner_000 + axis[0];
    float4 corner_010 = corner_000 + axis[1];
    float4 corner_110 = corner_010 + axis[0];
    float4 corner_001 = corner_000 + axis[2];
    float4 corner_101 = corner_100 + axis[2];
    float4 corner_011 = corner_010 + axis[2];
    float4 corner_111 = corner_110 + axis[2];

    float4 rect_min;
    rect_min = min(corner_000, corner_100);
    rect_min = min(rect_min, corner_010);
    rect_min = min(rect_min, corner_110);
    rect_min = min(rect_min, corner_001);
    rect_min = min(rect_min, corner_101);
    rect_min = min(rect_min, corner_011);
    rect_min = min(rect_min, corner_111);

    float4 rect_max;
    rect_max = max(corner_000, corner_100);
    rect_max = max(rect_max, corner_010);
    rect_max = max(rect_max, corner_110);
    rect_max = max(rect_max, corner_001);
    rect_max = max(rect_max, corner_101);
    rect_max = max(rect_max, corner_011);
    rect_max = max(rect_max, corner_111);

    float3 center = mul(float4(localBoundsOrigin, 1.0), worldMatrix).xyz;
    corner_000.xyz = rect_min.xyz;
    corner_100.xyz = float3(rect_max.x, rect_min.yz);
    corner_010.xyz = float3(rect_min.x, rect_max.y, rect_min.z);
    corner_110.xyz = float3(rect_max.xy, rect_min.z);
    corner_001.xyz = float3(rect_min.xy, rect_max.z);
    corner_101.xyz = float3(rect_max.x, rect_min.y, rect_max.z);
    corner_011.xyz = float3(rect_min.x, rect_max.yz);
    corner_111.xyz = rect_max.xyz;

    // Front quad
    DrawLine(corner_000, corner_100, float4(1, 0, 0, 1 * color.a), float4(1, 0, 0, 1 * color.a));
    DrawLine(corner_100, corner_110, color, color);
    DrawLine(corner_110, corner_010, color, color);
    DrawLine(corner_010, corner_000, float4(0, 1, 0, 1 * color.a), float4(0, 1, 0, 1 * color.a));
    // Back quad
    DrawLine(corner_001, corner_101, color, color);
    DrawLine(corner_101, corner_111, color, color);
    DrawLine(corner_111, corner_011, color, color);
    DrawLine(corner_011, corner_001, color, color);
    // Bottom/Top Connections
    DrawLine(corner_000, corner_001, float4(0, 0, 1, 1 * color.a), float4(0, 0, 1, 1 * color.a));
    DrawLine(corner_100, corner_101, color, color);
    DrawLine(corner_010, corner_011, color, color);
    DrawLine(corner_110, corner_111, color, color);
}

void DrawBoundingSphere(float3 localBoundsOrigin, float3 localBoundsExtents, float4x4 worldMatrix, float4 color = float4(1, 1, 1, 1), uint segments = 12)
{
    float3 ext = localBoundsExtents * 2.0f;
    float4x4 extents_basis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(extents_basis, worldMatrix);

    float4 corner_000 = mul(float4(localBoundsOrigin - localBoundsExtents, 1), worldMatrix);
    float4 corner_100 = corner_000 + axis[0];
    float4 corner_010 = corner_000 + axis[1];
    float4 corner_110 = corner_010 + axis[0];
    float4 corner_001 = corner_000 + axis[2];
    float4 corner_101 = corner_100 + axis[2];
    float4 corner_011 = corner_010 + axis[2];
    float4 corner_111 = corner_110 + axis[2];

    float4 rect_min;
    rect_min = min(corner_000, corner_100);
    rect_min = min(rect_min, corner_010);
    rect_min = min(rect_min, corner_110);
    rect_min = min(rect_min, corner_001);
    rect_min = min(rect_min, corner_101);
    rect_min = min(rect_min, corner_011);
    rect_min = min(rect_min, corner_111);

    float4 rect_max;
    rect_max = max(corner_000, corner_100);
    rect_max = max(rect_max, corner_010);
    rect_max = max(rect_max, corner_110);
    rect_max = max(rect_max, corner_001);
    rect_max = max(rect_max, corner_101);
    rect_max = max(rect_max, corner_011);
    rect_max = max(rect_max, corner_111);

    float3 center = mul(float4(localBoundsOrigin, 1.0), worldMatrix).xyz;
    float radius = rect_max.x - rect_min.x;
    radius = max(radius, rect_max.y - rect_min.y);
    radius = max(radius, rect_max.z - rect_min.z);

    float radiansStep = MATH_TAU / (float)segments;
    for (uint s = 0; s < segments; s++)
    {
        float3 direction1 = 0;
        float3 direction2 = 0;

        direction1 = RotateAboutAxis(float3(0, 1, 0), float3(0, 0, 1), s * radiansStep);
        direction2 = RotateAboutAxis(float3(0, 1, 0), float3(0, 0, 1), (s + 1) * radiansStep);
        DrawLine(center + direction1 * radius, center + direction2 * radius, color, color);

        direction1 = RotateAboutAxis(float3(1, 0, 0), float3(0, 1, 0), s * radiansStep);
        direction2 = RotateAboutAxis(float3(1, 0, 0), float3(0, 1, 0), (s + 1) * radiansStep);
        DrawLine(center + direction1 * radius, center + direction2 * radius, color, color);

        direction1 = RotateAboutAxis(float3(0, 0, 1), float3(1, 0, 0), s * radiansStep);
        direction2 = RotateAboutAxis(float3(0, 0, 1), float3(1, 0, 0), (s + 1) * radiansStep);
        DrawLine(center + direction1 * radius, center + direction2 * radius, color, color);
    }
}

#endif // _DEBUG_LINE_RENDERING_HLSLI_