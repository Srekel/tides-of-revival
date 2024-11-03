#ifndef _LIT_RESOURCES_H
#define _LIT_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"
#include "material.hlsl"

struct InstanceData
{
	float4x4 worldMat;
	float4x4 worldMatInverted;
	uint materialBufferOffset;
	float3 _padding;
};

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b1, binding = 0)
{
	DATA(float4x4, projView, None);
	DATA(float4x4, projViewInverted, None);
	DATA(float4, camPos, None);
	DATA(float, time, None);
};

PUSH_CONSTANT(RootConstant, b0)
{
	DATA(uint, startInstanceLocation, None);
	DATA(uint, instanceDataBufferIndex, None);
	DATA(uint, materialBufferIndex, None);
};

#if defined(VL_PosNorTanUv0Col)

STRUCT(VSInput)
{
	DATA(float4, Position, POSITION);
	DATA(uint, Normal, NORMAL);
	DATA(float4, Tangent, TANGENT);
	DATA(uint, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float3, PositionWS, POSITION);
	DATA(float3, Normal, NORMAL);
	DATA(float4, Tangent, TANGENT);
	DATA(float2, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
	DATA(uint, InstanceID, SV_InstanceID);
};

#elif defined(VL_PosNorTanUv0ColUv1)

STRUCT(VSInput)
{
	DATA(float4, Position, POSITION);
	DATA(uint, Normal, NORMAL);
	DATA(float4, Tangent, TANGENT);
	DATA(uint, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
	DATA(float2, UV1, TEXCOORD1);
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float3, PositionWS, POSITION);
	DATA(float3, Normal, NORMAL);
	DATA(float4, Tangent, TANGENT);
	DATA(float2, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
	DATA(float2, UV1, TEXCOORD1);
	DATA(uint, InstanceID, SV_InstanceID);
};

#endif

STRUCT(GBufferOutput)
{
	DATA(float4, GBuffer0, SV_TARGET0);
	DATA(float4, GBuffer1, SV_TARGET1);
	DATA(float4, GBuffer2, SV_TARGET2);
};

#endif // _LIT_RESOURCES_H