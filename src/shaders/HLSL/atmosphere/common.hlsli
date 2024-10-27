// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere
#pragma once

#include "../../FSL/d3d.h"

cbuffer FrameBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
	float4x4 view_proj_mat;

	float4 color;

	float3 sun_illuminance;
	int scattering_max_path_depth;

	uint2 resolution;
	float frame_time_sec;
	float time_sec;

	float2 ray_march_min_max_spp;
	float2 pad;
};

Texture2D<float4> texture_2d : register(t0, UPDATE_FREQ_PER_FRAME);
Texture2D<float4> blue_noise_2d_texture : register(t1, UPDATE_FREQ_PER_FRAME);

RWTexture2D<float4> rw_texture_2d : register(u0, UPDATE_FREQ_PER_FRAME);

SamplerState sampler_linear_clamp : register(s0, UPDATE_FREQ_PER_FRAME);
// TODO(gmodarelli): Enable Shadow Map
// SamplerComparisonState sampler_shadow : register(s1, UPDATE_FREQ_PER_FRAME);

struct VertexInput
{
	float4 position	: POSITION;
};

struct VertexOutput
{
	float4 position	: SV_POSITION;
	nointerpolation uint slice_id : SLICEINDEX;
};