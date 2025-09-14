#ifndef _SHADOWS_LIT_RESOURCES_H
#define _SHADOWS_LIT_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"
#include "types.hlsli"
#include "material.hlsli"

SamplerState g_linear_repeat_sampler : register(s0);
SamplerState g_linear_clamp_edge_sampler : register(s1);

cbuffer RootConstant : register(b0)
{
	InstanceRootConstants g_instanceRootConstants;
};

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_view_mat;
	float g_time;
};

#endif // _SHADOWS_LIT_RESOURCES_H