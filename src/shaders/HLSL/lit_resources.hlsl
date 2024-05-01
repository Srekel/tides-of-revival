#ifndef _LIT_RESOURCES_H
#define _LIT_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

struct InstanceData
{
	float4x4 worldMat;
	uint materialBufferOffset;
};

struct InstanceMaterial
{
	float4 baseColor;
	float roughness;
	float metallic;
	float normalIntensity;
	float emissiveStrength;
	uint baseColorTextureIndex;
	uint emissiveTextureIndex;
	uint normalTextureIndex;
	uint armTextureIndex;
};

static const uint INVALID_TEXTURE_INDEX = 0xFFFFFFFF;

bool hasValidTexture(uint textureIndex)
{
	return textureIndex != INVALID_TEXTURE_INDEX;
}

RES(SamplerState, bilinearRepeatSampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, bilinearClampSampler, UPDATE_FREQ_NONE, s1, binding = 2);

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b1, binding = 0)
{
	DATA(float4x4, projView, None);
	DATA(float4x4, projViewInverted, None);
	DATA(float4, camPos, None);
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
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float3, PositionWS, POSITION);
	DATA(float3, Normal, NORMAL);
	DATA(float3, Tangent, TANGENT);
	DATA(float2, UV, TEXCOORD0);
	DATA(uint, InstanceID, SV_InstanceID);
};

STRUCT(GBufferOutput)
{
	DATA(float4, GBuffer0, SV_TARGET0);
	DATA(float4, GBuffer1, SV_TARGET1);
	DATA(float4, GBuffer2, SV_TARGET2);
};

// #include "pbr.h"

#endif // _LIT_RESOURCES_H