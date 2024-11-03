#ifndef _TERRAIN_RESOURCES_H
#define _TERRAIN_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

struct InstanceData
{
	float4x4 worldMat;
	uint heightmapTextureIndex;
	uint lod;
	uint2 _padding1;
};

struct TerrainLayerTextureIndices
{
	uint diffuseIndex;
	uint normalIndex;
	uint armIndex;
	uint heightIndex;
};

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);

PUSH_CONSTANT(RootConstant, b0)
{
	DATA(uint, startInstanceLocation, None);
	DATA(uint, instanceDataBufferIndex, None);
	DATA(uint, materialBufferIndex, None);
};

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b1, binding = 0)
{
	DATA(float4x4, projView, None);
	DATA(float4x4, projViewInverted, None);
	DATA(float4, camPos, None);
	DATA(float, triplanarMapping, None);
	DATA(float, blackPoint, None);
	DATA(float, whitePoint, None);
	DATA(float, _padding, None);
};

STRUCT(VSInput)
{
	DATA(float4, Position, POSITION);
	DATA(uint, UV, TEXCOORD0);
	DATA(float4, Color, COLOR);
};

STRUCT(VSOutput)
{
	DATA(float4, Position, SV_Position);
	DATA(float3, PositionWS, POSITION);
	DATA(float2, UV, TEXCOORD0);
	DATA(float3, Normal, TEXCOORD1);
	DATA(uint, InstanceID, SV_InstanceID);
};

STRUCT(GBufferOutput)
{
	DATA(float4, GBuffer0, SV_TARGET0);
	DATA(float4, GBuffer1, SV_TARGET1);
	DATA(float4, GBuffer2, SV_TARGET2);
};

#endif // _TERRAIN_RESOURCES_H