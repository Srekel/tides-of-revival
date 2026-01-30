#ifndef _TERRAIN_RESOURCES_H
#define _TERRAIN_RESOURCES_H

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"
#include "types.hlsli"

struct TerrainLayerTextureIndices
{
	uint diffuseIndex;
	uint normalIndex;
	uint armIndex;
	uint heightIndex;
};

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);

cbuffer RootConstant : register(b0)
{
	InstanceRootConstants g_instanceRootConstants;
};

cbuffer cbFrame : register(b1, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_proj_view_mat;
	float4x4 g_inv_proj_view_mat;
	float4 g_cam_pos;
	float g_black_point;
	float g_white_point;
	float g_tiling_distance_max;
	uint g_rust_texture_index;
};

cbuffer cbMaterial : register(b2, UPDATE_FREQ_PER_FRAME)
{
	TerrainLayerTextureIndices g_layers[4];
};

#endif // _TERRAIN_RESOURCES_H