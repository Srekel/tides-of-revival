#ifndef _GPU_DRIVEN_RESOURCES_H
#define _GPU_DRIVEN_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"
#include "types.hlsli"
// #include "material.hlsli"

struct VSOutput
{
	float4 Position : SV_Position;
	float3 Normal : TEXCOORD0;
	float2 UV : TEXCOORD1;
	uint InstanceID : SV_InstanceID;
};

struct Vertex
{
	float3 position;
	float3 normal;
	float4 tangent;
	float2 uv;
};

SamplerState g_linear_repeat_sampler : register(s0);
SamplerState g_linear_clamp_edge_sampler : register(s1);

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_ProjView;
	float4x4 g_ProjViewInv;
	float4 g_Camera;
	float g_Time;
	uint g_InstanceBufferIndex;
	uint g_InstanceIndirectionBufferIndex;
	uint g_GpuMeshBufferIndex;
	uint g_VertexBufferIndex;
	uint g_MaterialBufferIndex;
};

#endif // _GPU_DRIVEN_RESOURCES_H