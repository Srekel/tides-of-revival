#ifndef _UI_RESOURCES_H
#define _UI_RESOURCES_H

#include "../FSL/d3d.h"

static const uint top = 0;
static const uint bottom = 1;
static const uint left = 2;
static const uint right = 3;

static const uint quadVertexCount = 4;
static const uint2 quadVertexPositions[quadVertexCount] = {
    uint2(left, top),
    uint2(right, bottom),
    uint2(left, bottom),
    uint2(right, top)
};

static const float2 quadVertexUVs[quadVertexCount] = {
    float2(0.0, 0.0),
    float2(1.0, 1.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0)
};

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);

cbuffer cbFrame : register(b0, UPDATE_FREQ_PER_FRAME)
{
	float4x4 g_screen_to_clip_mat;
	uint g_ui_transform_buffer_index;
};

struct UITransform
{
    float4 rect;
    float4 color;
    uint textureIndex;
    float3 _padding;
};

STRUCT(VSOutput)
{
    DATA(float4, Position, SV_Position);
    DATA(float2, UV, TEXCOORD0);
    DATA(uint, InstanceID, SV_InstanceID);
};

#endif // _UI_RESOURCES_H