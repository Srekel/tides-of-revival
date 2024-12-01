#ifndef _TERRAIN_RESOURCES_H
#define _TERRAIN_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

struct InstanceData
{
	float4x4 worldMat;
	uint heightmapTextureIndex;
	uint normalmapTextureIndex;
	uint lod;
	uint _padding1;
};

struct TerrainLayerTextureIndices
{
	uint diffuseIndex;
	uint normalIndex;
	uint armIndex;
	uint heightIndex;
};

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);

cbuffer RootConstant : register(b0)
{
	uint g_start_instance_location;
	uint g_instance_data_buffer_index;
};

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_view_mat;
	float4x4 g_inv_proj_view_mat;
	float4 g_cam_pos;
	float g_black_point;
	float g_white_point;
	float2 _padding;
};

cbuffer cbMaterial : register(b2, UPDATE_FREQ_PER_FRAME)
{
	TerrainLayerTextureIndices g_layers[4];
};

STRUCT(VSInput)
{
	DATA(float4, Position, POSITION);
	DATA(uint, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float3, PositionWS, POSITION);
	DATA(float2, UV, TEXCOORD0);
	DATA(float3, Normal, TEXCOORD1);
	DATA(uint, InstanceID, SV_InstanceID);
};

STRUCT(GBufferOutput)
{
	DATA(float4, GBuffer0, SV_TARGET0);
	DATA(float4, GBuffer1, SV_TARGET1);
	DATA(float4, GBuffer2, SV_TARGET2);
};

#endif // _TERRAIN_RESOURCES_H