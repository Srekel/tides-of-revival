#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"
#include "utils.hlsl"

// ████████╗ ██████╗ ███╗   ██╗██╗   ██╗    ███╗   ███╗ ██████╗    ███╗   ███╗ █████╗ ██████╗ ███████╗ █████╗  ██████╗███████╗
// ╚══██╔══╝██╔═══██╗████╗  ██║╚██╗ ██╔╝    ████╗ ████║██╔════╝    ████╗ ████║██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔════╝██╔════╝
//    ██║   ██║   ██║██╔██╗ ██║ ╚████╔╝     ██╔████╔██║██║         ██╔████╔██║███████║██████╔╝█████╗  ███████║██║     █████╗
//    ██║   ██║   ██║██║╚██╗██║  ╚██╔╝      ██║╚██╔╝██║██║         ██║╚██╔╝██║██╔══██║██╔═══╝ ██╔══╝  ██╔══██║██║     ██╔══╝
//    ██║   ╚██████╔╝██║ ╚████║   ██║       ██║ ╚═╝ ██║╚██████╗    ██║ ╚═╝ ██║██║  ██║██║     ██║     ██║  ██║╚██████╗███████╗
//    ╚═╝    ╚═════╝ ╚═╝  ╚═══╝   ╚═╝       ╚═╝     ╚═╝ ╚═════╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝
//
// https://github.com/h3r2tic/tony-mc-mapface
float3 tony_mc_mapface(float3 stimulus, Texture3D<float3> lut, SamplerState linear_clamp_edge)
{
    // Apply a non-linear transform that the LUT is encoded with.
    const float3 encoded = stimulus / (stimulus + 1.0);

    // Align the encoded range to texel centers.
    const float LUT_DIMS = 48.0;
    const float3 uv = encoded * ((LUT_DIMS - 1.0) / LUT_DIMS) + 0.5 / LUT_DIMS;

    // Note: for OpenGL, do `uv.y = 1.0 - uv.y`

    return lut.SampleLevel(linear_clamp_edge, uv, 0);
}

cbuffer ConstantBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
    // Color Grading settings
    float3 g_color_filter;
    float g_post_exposure;
    float g_contrast;
    float g_hue_shift;
    float g_saturation;
    // Tonemapper LUT
    uint g_tony_mc_mapface_lut_index;
};

SamplerState g_linear_clamp_edge_sampler : register(s0, UPDATE_FREQ_NONE);
Texture2D<float4> g_scene_color : register(t0, UPDATE_FREQ_PER_FRAME);

struct VsOut
{
	float4 Position : SV_Position;
	float2 UV : TEXCOORD0;
};

float3 ColorGradePostExposure(float3 color)
{
    return color * g_post_exposure;
}

float3 ColorGradeContrast(float3 color)
{
    const float acescc_midgray = 0.4135884f;
    color = LinearToLogC(color);
    color = (color - acescc_midgray) * g_contrast + acescc_midgray;
    return LogCToLinear(color);
}

float3 ColorGradeColorFilter(float3 color)
{
    return color * g_color_filter;
}

float3 ColorGradeSaturation(float3 color)
{
    float luminance = Luminance(color);
    return (color - luminance) * g_saturation + luminance;
}

float4 PS_MAIN(VsOut Input) : SV_TARGET {
    float4 Out = float4(0, 0, 0, 1);

    float3 color = SampleLvlTex2D(g_scene_color, g_linear_clamp_edge_sampler, Input.UV, 0).rgb;

    // Color Grading
    color = min(color, 60.0);
    color = ColorGradePostExposure(color);
    color = ColorGradeContrast(color);
    color = ColorGradeColorFilter(color);
    color = max(color, 0.0);
    color = ColorGradeSaturation(color);
    color = max(color, 0.0);

    // Tone mapping
    Texture3D<float3> tony_mc_mapface_lut = ResourceDescriptorHeap[g_tony_mc_mapface_lut_index];
    color = tony_mc_mapface(color, tony_mc_mapface_lut, g_linear_clamp_edge_sampler);
    Out.rgb = color;

    return Out;
}
