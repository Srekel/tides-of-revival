#ifndef _WATER_RESOURCES_H
#define _WATER_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

SamplerState g_linear_repeat_sampler : register(s0, UPDATE_FREQ_NONE);
SamplerState g_linear_clamp_edge_sampler : register(s1, UPDATE_FREQ_NONE);

cbuffer RootConstant : register(b0)
{
	uint g_start_instance_location;
	uint g_instance_data_buffer_index;
    // TODO(gmodarelli): Add materials
	// uint g_material_buffer_index;
};

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_view_mat;
	float4x4 g_inv_proj_view_mat;
	float4 g_cam_pos;
	float g_time;
};

struct VSInput
{
	float4 Position : POSITION;
	uint Normal : NORMAL;
	float4 Tangent : TANGENT;
	uint UV : TEXCOORD0;
	float4 Color : COLOR;
};

struct VSOutput
{
	float4 Position : SV_Position;
	float3 PositionWS : POSITION;
	float3 Normal : NORMAL;
	float4 Tangent : TANGENT;
	float2 UV : TEXCOORD0;
	float4 Color : COLOR;
	uint InstanceID : SV_InstanceID;
};

struct InstanceData
{
	float4x4 worldMat;
	float4x4 worldMatInverted;
	uint materialBufferOffset;
	float3 _padding;
};

#endif // _WATER_RESOURCES_H
