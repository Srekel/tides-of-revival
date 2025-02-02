#ifndef _WATER_RESOURCES_H
#define _WATER_RESOURCES_H

#include "../FSL/d3d.h"
#include "types.hlsli"

SamplerState g_linear_repeat_sampler : register(s0, UPDATE_FREQ_NONE);
SamplerState g_linear_clamp_edge_sampler : register(s1, UPDATE_FREQ_NONE);

Texture2D<float2> g_brdf_integration_map : register(t0, UPDATE_FREQ_PER_FRAME);
TextureCube<float4> g_irradiance_map : register(t1, UPDATE_FREQ_PER_FRAME);
TextureCube<float4> g_specular_map : register(t2, UPDATE_FREQ_PER_FRAME);

Texture2D<float4> g_scene_color : register(t3, UPDATE_FREQ_PER_FRAME);
Texture2D<float> g_depth_buffer : register(t4, UPDATE_FREQ_PER_FRAME);

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
	float g_time;
};

cbuffer cbLight : register(b2, UPDATE_FREQ_PER_FRAME)
{
    // TODO(gmodarelli): Use light buffers
	float4 g_sun_color_intensity;
	float3 g_sun_direction;
	float _padding1;
}

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

struct WaterMaterial
{
    float3 m_absorption_color;
    float m_absorption_coefficient;

    uint m_normal_map_1_texture_index;
    uint m_normal_map_2_texture_index;
    float m_surface_roughness;
	float m_surface_opacity;

    float4 m_normal_map_1_params;
    float4 m_normal_map_2_params;
};

#endif // _WATER_RESOURCES_H
