#ifndef _MESH_SHADING_MESHLET_RASTERIZER_HLSLI_
#define _MESH_SHADING_MESHLET_RASTERIZER_HLSLI_

#include "../../FSL/d3d.h"
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
    uint primitive_id : SV_PrimitiveID;
    uint candidate_index : CANDIDATE_INDEX;
};

struct VertexAttribute
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

struct RasterizerParams
{
    uint bin_index;
    uint visible_meshlets_buffer_index;
    uint binned_meshlets_buffer_index;
    uint meshlet_bin_data_buffer_index;
};

cbuffer g_Frame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    Frame g_Frame;
};

cbuffer g_RasterizerParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    RasterizerParams g_rasterizer_params;
};

Instance getInstance(uint instance_index)
{
    ByteAddressBuffer instance_buffer = ResourceDescriptorHeap[g_Frame.instance_buffer_index];
    Instance instance = instance_buffer.Load<Instance>(instance_index * sizeof(Instance));
    return instance;
}

MaterialData getMaterial(uint material_index)
{
    ByteAddressBuffer material_buffer = ResourceDescriptorHeap[g_Frame.material_buffer_index];
    MaterialData material = material_buffer.Load<MaterialData>(material_index * sizeof(MaterialData));
    return material;
}

VertexAttribute FetchVertexAttribute(Mesh mesh, float4x4 world, uint vertex_id)
{
    VertexAttribute attribute = (VertexAttribute)0;
    ByteAddressBuffer data_buffer = ResourceDescriptorHeap[NonUniformResourceIndex(mesh.data_buffer_index)];
    float3 position = data_buffer.Load<float3>(vertex_id * sizeof(float3) + mesh.positions_offset);
    float3 position_ws = mul(float4(position, 1.0f), world).xyz;
    attribute.position = mul(float4(position_ws, 1.0f), g_Frame.view_proj);
    float2 uv = data_buffer.Load<float2>(vertex_id * sizeof(float2) + mesh.texcoords_offset);
    attribute.uv = uv;
    return attribute;
}

#endif // _MESH_SHADING_MESHLET_RASTERIZER_HLSLI_