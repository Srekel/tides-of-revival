#ifndef _DRAW_SKY_RESOURCES
#define _DRAW_SKY_RESOURCES

#include "../../FSL/d3d.h"

struct VSInput
{
    float4 Position : POSITION;
    float2 UV : TEXCOORD0;
    float4 Color : COLOR;
};

struct VSOutput
{
    float4 Position : SV_Position;
    float3 UV : TEXCOORD0;
};

SamplerState g_linear_repeat_sampler : register(s0);

cbuffer FrameBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_proj_mat;
    float4x4 g_view_mat;
};

TextureCube<float4> skybox_cubemap : register(t0, UPDATE_FREQ_PER_FRAME);

#endif // _DRAW_SKY_RESOURCES