#ifndef _MESH_SHADING_MESHLET_RASTERIZER_HLSLI_
#define _MESH_SHADING_MESHLET_RASTERIZER_HLSLI_

#include "../../FSL/d3d.h"
#include "../utils.hlsli"
#include "defines.hlsli"
#include "types.hlsli"

struct GBufferOutput
{
    float4 GBuffer0 : SV_TARGET0;
    float4 GBuffer1 : SV_TARGET1;
    float4 GBuffer2 : SV_TARGET2;
};

struct PrimitiveAttribute
{
    uint primitiveId : SV_PrimitiveID;
    uint candidateIndex : CANDIDATE_INDEX;
};

struct VertexAttribute
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float3 positionWS : TEXCOORD1;
    float4 tangent : TEXCOORD2;
    float3 normal : TEXCOORD3;
    float4 color : TEXCOORD4;
};

struct RasterizerParams
{
    uint binIndex;
    uint visibleMeshletsBufferIndex;
    uint binnedMeshletsBufferIndex;
    uint meshletBinDataBufferIndex;
};

cbuffer g_Frame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    Frame g_Frame;
};

cbuffer g_RasterizerParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    RasterizerParams g_RasterizerParams;
};

Instance getInstance(uint instance_index)
{
    ByteAddressBuffer instance_buffer = ResourceDescriptorHeap[g_Frame.instanceBufferIndex];
    Instance instance = instance_buffer.Load<Instance>(instance_index * sizeof(Instance));
    return instance;
}

MaterialData getMaterial(uint material_index)
{
    ByteAddressBuffer material_buffer = ResourceDescriptorHeap[g_Frame.materialBufferIndex];
    MaterialData material = material_buffer.Load<MaterialData>(material_index * sizeof(MaterialData));
    return material;
}

VertexAttribute FetchVertexAttribute(Mesh mesh, float4x4 world, uint vertex_id)
{
    VertexAttribute attribute = (VertexAttribute)0;
    ByteAddressBuffer data_buffer = ResourceDescriptorHeap[NonUniformResourceIndex(mesh.dataBufferIndex)];
    float3 position = data_buffer.Load<float3>(vertex_id * sizeof(float3) + mesh.positionsOffset);
    float3 position_ws = mul(float4(position, 1.0f), world).xyz;
    attribute.position = mul(float4(position_ws, 1.0f), g_Frame.viewProj);
    attribute.positionWS = position_ws;
    attribute.uv = data_buffer.Load<float2>(vertex_id * sizeof(float2) + mesh.texcoordsOffset);
    attribute.normal = data_buffer.Load<float3>(vertex_id * sizeof(float3) + mesh.normalsOffset);
    attribute.tangent = data_buffer.Load<float4>(vertex_id * sizeof(float4) + mesh.tangentsOffset);
    attribute.color = float4(1, 1, 1, 1);
    return attribute;
}

#endif // _MESH_SHADING_MESHLET_RASTERIZER_HLSLI_