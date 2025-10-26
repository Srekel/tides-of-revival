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
    float3 SunPosition : TEXCOORD1;
    float3 MoonPosition : TEXCOORD2;
};

SamplerState g_linear_repeat_sampler : register(s0);
SamplerState g_linear_clamp_edge_sampler : register(s1);

cbuffer FrameBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_proj_mat;
    float4x4 g_view_mat;
    float4x4 g_sun_mat;
    float4x4 g_moon_mat;
    float3 sun_direction;
    float sun_intensity;
    float3 moon_direction;
    float moon_intensity;
    float3 sun_color;
    uint g_moon_texture_index;
    float g_time_of_day_01;
    float g_time;
    float2 g_pad0;
};

TextureCube<float4> skybox_cubemap : register(t0, UPDATE_FREQ_PER_FRAME);
TextureCube<float4> starfield_cubemap : register(t1, UPDATE_FREQ_PER_FRAME);

#endif // _DRAW_SKY_RESOURCES