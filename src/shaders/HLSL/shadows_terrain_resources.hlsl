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

RES(SamplerState, bilinearRepeatSampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, bilinearClampSampler, UPDATE_FREQ_NONE, s1, binding = 2);

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b1, binding = 0)
{
	DATA(float4x4, projView, None);
};

PUSH_CONSTANT(RootConstant, b0)
{
	DATA(uint, startInstanceLocation, None);
	DATA(uint, instanceDataBufferIndex, None);
	DATA(uint, materialBufferIndex, None);
};

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
};

#endif // _SHADOWS_TERRAIN_RESOURCES_H