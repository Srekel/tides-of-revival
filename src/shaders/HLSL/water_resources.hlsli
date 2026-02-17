#ifndef _WATER_RESOURCES_H
#define _WATER_RESOURCES_H

#include "../FSL/d3d.h"
#include "types.hlsli"

SamplerState g_linear_repeat_sampler : register(s0, UPDATE_FREQ_NONE);
SamplerState g_linear_clamp_edge_sampler : register(s1, UPDATE_FREQ_NONE);

Texture2D<float4> g_scene_color : register(t0, UPDATE_FREQ_PER_FRAME);
Texture2D<float> g_depth_buffer : register(t1, UPDATE_FREQ_PER_FRAME);
StructuredBuffer<GpuLight> lights : register(t2, UPDATE_FREQ_PER_FRAME);

cbuffer RootConstant : register(b0)
{
	InstanceRootConstants g_instanceRootConstants;
};

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_mat;
	float4x4 g_proj_view_mat;
	float4x4 g_inv_proj_view_mat;
	float4 g_cam_pos;
	float4 g_depth_buffer_params;
	uint g_lights_count;
	float g_time;
	uint m_caustics_texture_index;
	uint _pad0;
	float3 g_fog_color;
	float g_fog_density;

	// Water material
	float3 m_water_fog_color;
	float m_water_density;
	float4 m_normal_map_1_params;
	float4 m_normal_map_2_params;

	uint m_normal_map_1_texture_index;
	uint m_normal_map_2_texture_index;
	float m_surface_roughness;
	float m_refraction_strength;
};

struct VSInput
{
	float4 Position : POSITION;
	float3 Normal : NORMAL;
	float4 Tangent : TANGENT;
	float2 UV : TEXCOORD0;
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

#endif // _WATER_RESOURCES_H
