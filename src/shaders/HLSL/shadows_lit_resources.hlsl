#ifndef _SHADOWS_LIT_RESOURCES_H
#define _SHADOWS_LIT_RESOURCES_H

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

RES(SamplerState, bilinearRepeatSampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, bilinearClampSampler, UPDATE_FREQ_NONE, s1, binding = 2);

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b1, binding = 0)
{
	DATA(float4x4, projView, None);
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
	DATA(uint, Tangent, TANGENT);
	DATA(uint, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float2, UV, TEXCOORD0);
	DATA(uint, InstanceID, SV_InstanceID);
};

#elif defined(VL_PosNorTanUv0ColUv1)

STRUCT(VSInput)
{
	DATA(float4, Position, POSITION);
	DATA(uint, Normal, NORMAL);
	DATA(uint, Tangent, TANGENT);
	DATA(uint, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
	DATA(float2, UV1, TEXCOORD1);
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float2, UV, TEXCOORD0);
	DATA(float2, UV1, TEXCOORD1);
	DATA(uint, InstanceID, SV_InstanceID);
};

#endif

#endif // _SHADOWS_LIT_RESOURCES_H