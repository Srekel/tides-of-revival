#ifndef _SKYBOX_RESOURCES_H
#define _SKYBOX_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b0, binding = 0)
{
	DATA(float4x4, projView,          None);
	DATA(float4x4, projViewInverted,  None);
	DATA(float4,   camPos,            None);
};

RES(TexCube(float4), skyboxMap, UPDATE_FREQ_NONE, t0, binding = 0);
RES(SamplerState, bilinearRepeatSampler, UPDATE_FREQ_NONE, s0, binding = 1);

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