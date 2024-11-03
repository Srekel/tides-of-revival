#ifndef _SHADOWS_TERRAIN_RESOURCES_H
#define _SHADOWS_TERRAIN_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

struct InstanceData
{
	float4x4 worldMat;
	uint heightmapTextureIndex;
	uint splatmapTextureIndex;
	uint lod;
	uint _padding1;
};

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);

cbuffer RootConstant : register(b0)
{
	uint g_start_instance_location;
	uint g_instance_data_buffer_index;
	uint g_material_buffer_index;
};

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_view_mat;
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
	DATA(float2, UV, TEXCOORD0);
};

#endif // _SHADOWS_TERRAIN_RESOURCES_H