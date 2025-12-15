#ifndef _MESH_SHADING_TYPES_HLSLI_
#define _MESH_SHADING_TYPES_HLSLI_

#include "../material.hlsli"

struct Frame
{
    float4x4 view;
    float4x4 projection;
    float4x4 viewProj;
    float4x4 viewProjInv;

    float4 viewportInfo; // xy: size, zw: inv_size
    float4 cameraPosition;
    float cameraNearPlane;
    float cameraFarPlane;
    float time;
    uint renderableBufferIndex;

    // Default samplers
    // TODO: Add more default samplers
    uint linearRepeatSamplerIndex;
    uint linearClampSamplerIndex;
    uint shadowSamplerIndex;
    uint shadowPcfSamplerIndex;

    uint instanceBufferIndex;
    uint materialBufferIndex;
    uint meshesBufferIndex;
    uint instancesCount;
};

struct Mesh
{
    uint dataBufferIndex;
    uint positionsOffset;
    uint normalsOffset;
    uint texcoordsOffset;
    uint tangentsOffset;
    uint indicesOffset;
    uint indexByteSize;
    uint meshletOffset;
    uint meshletVertexOffset;
    uint meshletTriangleOffset;
    uint meshletBoundsOffset;
    uint meshletCount;
};

struct Meshlet
{
    uint vertexOffset;
    uint triangleOffset;
    uint vertexCount;
    uint triangleCount;
};

struct MeshletTriangle
{
    uint v0 : 10;
    uint v1 : 10;
    uint v2 : 10;
    uint _pad : 2;
};

struct MeshletBounds
{
    float3 localCenter;
    float3 localExtents;
};

struct MeshletCandidate
{
    uint instanceId;
    uint meshIndex;
    uint materialIndex;
    uint meshletIndex;
};

struct OldInstance
{
    float4x4 world;
    float3 localBoundsOrigin;
    float screenPercentageMin;
    float3 localBoundsExtents;
    float screenPercentageMax;
    uint id;
    uint meshIndex;
    uint materialIndex;
    uint flags;
};

struct Instance
{
    float4x4 world;
    float3 boundsOrigin;
    uint renderableItemIndex;
    float3 boundsExtents;
    uint renderableItemCount;
    uint flags;
};

struct RenderableItem
{
    float3 localBoundsOrigin;
    float screenPercentageMin;
    float3 localBoundsExtents;
    float screenPercentageMax;
    uint meshIndex;
    uint materialIndex;
    uint2 _pad;
};

#endif // _MESH_SHADING_TYPES_HLSLI_