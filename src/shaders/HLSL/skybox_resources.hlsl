#ifndef _SKYBOX_RESOURCES_H
#define _SKYBOX_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

cbuffer cbFrame : register(b0, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_view_mat;
	float4x4 g_inv_proj_view_mat;
	float4   g_cam_pos;
};

RES(TexCube(float4), skyboxMap, UPDATE_FREQ_NONE, t0, binding = 0);
RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);

STRUCT(VSInput) {
	DATA(float4, Position, POSITION);
	DATA(uint, Normal, NORMAL);
	DATA(float4, Tangent, TANGENT);
	DATA(uint, UV, TEXCOORD0);
};

STRUCT(VSOutput) {
	DATA(float4, Position, SV_Position);
	DATA(float3, pos, POSITION);
};

#endif // _SKYBOX_RESOURCES_H