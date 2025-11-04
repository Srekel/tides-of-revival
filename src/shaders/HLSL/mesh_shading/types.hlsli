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
    float _pad0;

    // Default samplers
    // TODO: Add more default samplers
    uint linearRepeatSamplerIndex;
    uint linearClampSamplerIndex;
    uint shadowSamplerIndex;
    uint shadowPcfSamplerIndex;

    uint instancesCount;
    uint instanceBufferIndex;
    uint materialBufferIndex;
    uint meshesBufferIndex;

    uint renderableMeshBufferIndex;
    uint3 _pad1;
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
    uint meshletIndex;
};

struct Instance
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

struct RenderableMeshLodSubMesh
{
    // TODO: Packe meshIndex and materialIndex into a single u32
    uint meshIndex;
    uint materialIndex;
    uint2 _pad0;
};

struct RenderableMeshLod
{
    RenderableMeshLodSubMesh subMeshes[32];
    uint subMeshesCount;
    float screenPercentageMin;
    float screenPercentageMax;
    uint flags;
};

struct RenderableMesh
{
    RenderableMeshLod lods[4];
    uint lodsCount;
    uint3 _pad;
};

struct Instance2
{
    float4x4 world;
    float3 localBoundsOrigin;
    uint id;
    float3 localBoundsExtents;
    uint renderableMeshId;
};

struct MeshletCandidate2
{
    uint instanceId;
    uint meshletIndex;
    uint materialIndex;
    uint meshIndex;
};

#endif // _MESH_SHADING_TYPES_HLSLI_