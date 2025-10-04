#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"
#include "utils.hlsli"

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);
RES(SamplerState, g_point_repeat_sampler, UPDATE_FREQ_NONE, s2, binding = 3);

RES(Tex2D(float4), gBuffer0, UPDATE_FREQ_NONE, t0, binding = 4);
RES(Tex2D(float4), gBuffer1, UPDATE_FREQ_NONE, t1, binding = 5);
RES(Tex2D(float4), gBuffer2, UPDATE_FREQ_NONE, t2, binding = 6);
RES(Tex2D(float), depthBuffer, UPDATE_FREQ_NONE, t3, binding = 7);
RES(Tex2D(float), shadowDepthBuffer, UPDATE_FREQ_NONE, t4, binding = 8);

#define BRDF_FUNCTION FILAMENT_BRDF
#include "pbr.hlsli"

cbuffer cbFrame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_proj_view_mat;
    float4x4 g_inv_proj_view_mat;
    float4 g_cam_pos;
    uint g_lights_buffer_index;
    uint g_lights_count;
    uint2 _padding;
    float3 g_fog_color;
    float g_fog_density;
};

STRUCT(VsOut)
{
    DATA(float4, Position, SV_Position);
    DATA(float2, UV, TEXCOORD0);
};

float4 getClipPositionFromDepth(float depth, float2 uv)
{
    float x = uv.x * 2.0f - 1.0f;
    float y = (1.0f - uv.y) * 2.0f - 1.0f;
    float4 positionCS = float4(x, y, depth, 1.0f);
    return mul(g_inv_proj_view_mat, positionCS);
}

float3 getWorldPositionFromDepth(float depth, float2 uv)
{
    float4 positionCS = getClipPositionFromDepth(depth, uv);
    return positionCS.xyz / positionCS.w;
}

float4 PS_MAIN(VsOut Input) : SV_TARGET0
{
    INIT_MAIN;

    float4 baseColor = SampleLvlTex2D(Get(gBuffer0), Get(g_linear_clamp_edge_sampler), Input.UV, 0);
    if (baseColor.a <= 0)
    {
        RETURN(float4(0.0, 0.0, 0.0, 0.0));
    }

    float3 N = normalize(SampleLvlTex2D(Get(gBuffer1), Get(g_linear_clamp_edge_sampler), Input.UV, 0).rgb);
    float4 pbrSample = SampleLvlTex2D(Get(gBuffer2), Get(g_linear_clamp_edge_sampler), Input.UV, 0);
    float depth = SampleLvlTex2D(Get(depthBuffer), Get(g_linear_clamp_edge_sampler), Input.UV, 0).r;

    const float3 P = getWorldPositionFromDepth(depth, Input.UV);
    const float3 V = normalize(g_cam_pos.xyz - P);

    SurfaceInfo surfaceInfo;
    surfaceInfo.position = P;
    surfaceInfo.normal = N;
    surfaceInfo.view = V;
    surfaceInfo.albedo = baseColor.rgb;
    surfaceInfo.perceptual_roughness = max(0.04f, pbrSample.g);
    surfaceInfo.metallic = pbrSample.b;
    surfaceInfo.reflectance = pbrSample.a;

    float3 Lo = float3(0.0f, 0.0f, 0.0f);

    ByteAddressBuffer lightsBuffer = ResourceDescriptorHeap[g_lights_buffer_index];
    for (uint i = 0; i < g_lights_count; ++i)
    {
        GpuLight light = lightsBuffer.Load<GpuLight>(i * sizeof(GpuLight));
        Lo += ShadeLight(light, surfaceInfo, 1.0f);
    }

    // Simple depth-based fog
    float view_distance = length(g_cam_pos.xyz - P.xyz);
    float fog_factor = exp(-g_fog_density * view_distance);
    Lo = lerp(g_fog_color, Lo, saturate(fog_factor));

    RETURN(float4(Lo, 1.0f));
}
