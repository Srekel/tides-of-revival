#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"
#include "utils.hlsli"
#include "math.hlsli"

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);
RES(SamplerState, g_point_repeat_sampler, UPDATE_FREQ_NONE, s2, binding = 3);
RES(SamplerComparisonState, g_linear_clamp_cmp_greater_sampler, UPDATE_FREQ_NONE, s3, binding = 4);

RES(Tex2D(float4), gBuffer0, UPDATE_FREQ_NONE, t0, binding = 5);
RES(Tex2D(float4), gBuffer1, UPDATE_FREQ_NONE, t1, binding = 6);
RES(Tex2D(float4), gBuffer2, UPDATE_FREQ_NONE, t2, binding = 7);
RES(Tex2D(float), depthBuffer, UPDATE_FREQ_NONE, t3, binding = 8);
RES(Tex2D(float), shadowDepth0, UPDATE_FREQ_NONE, t4, binding = 9);
RES(Tex2D(float), shadowDepth1, UPDATE_FREQ_NONE, t5, binding = 10);
RES(Tex2D(float), shadowDepth2, UPDATE_FREQ_NONE, t6, binding = 11);
RES(Tex2D(float), shadowDepth3, UPDATE_FREQ_NONE, t7, binding = 12);

#define BRDF_FUNCTION FILAMENT_BRDF
#include "pbr.hlsli"

#define CASCADES_MAX_COUNT 4

cbuffer cbFrame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_proj_mat;
    float4x4 g_inv_proj_mat;
    float4x4 g_proj_view_mat;
    float4x4 g_inv_proj_view_mat;
    float4 g_cam_pos;
    float g_near_plane;
    float g_far_plane;
    float2 g_shadow_resolution_inverse;
    float4 g_cascade_depths;
    uint g_lights_buffer_index;
    uint g_lights_count;
    uint g_light_matrix_buffer_index;
    uint _padding1;
    float3 g_fog_color;
    float g_fog_density;
};

STRUCT(VsOut)
{
    DATA(float4, Position, SV_Position);
    DATA(float2, UV, TEXCOORD0);
};

float LinearizeDepth01(float z)
{
    return g_far_plane / (g_far_plane + z * (g_near_plane - g_far_plane));
}

float3 ViewPositionFromDepth(float2 uv, float depth, float4x4 projectionInverse)
{
    float4 clip = float4(float2(uv.x, 1.0f - uv.y) * 2.0f - 1.0f, 0.0f, 1.0f) * g_near_plane;
    float3 viewRay = mul(clip, projectionInverse).xyz;
    return viewRay * LinearizeDepth01(depth);
}

float3 WorldPositionFromDepth(float2 uv, float depth, float4x4 viewProjectionInverse)
{
    float4 clip = float4(float2(uv.x, 1.0f - uv.y) * 2.0f - 1.0f, depth, 1.0f);
    float4 world = mul(clip, viewProjectionInverse);
    return world.xyz / world.w;
}

uint GetSunShadowMapIndex(float viewDepth /*, float dither */)
{
    float4 splits = viewDepth > g_cascade_depths;
    float4 cascades = g_cascade_depths > 0;
    int cascadeIndex = min(dot(splits, cascades), CASCADES_MAX_COUNT - 1);

    // const float cascadeFadeTheshold = 0.1f;
    // float nextSplit = g_cascade_depths[cascadeIndex];
    // float splitRange = cascadeIndex == 0 ? nextSplit : nextSplit - g_cascade_depths[cascadeIndex - 1];
    // float fadeFactor = (nextSplit - viewDepth) / splitRange;
    // if (fadeFactor <= cascadeFadeTheshold && cascadeIndex < CASCADES_MAX_COUNT - 1)
    // {
    //     float lerpAmount = smoothstep(0.0f, cascadeFadeTheshold, fadeFactor);
    //     if (lerpAmount < dither)
    //     {
    //         cascadeIndex++;
    //     }
    // }

    return cascadeIndex;
}

float2 ClipToUV(float2 clip)
{
    return clip * float2(0.5f, -0.5f) + 0.5f;
}

float Shadow3x3PCF(float3 P, const int cascadeIndex, float invShadowSize)
{
    ByteAddressBuffer lightMatrixBuffer = ResourceDescriptorHeap[g_light_matrix_buffer_index];
    float4x4 lightViewProjection = lightMatrixBuffer.Load<float4x4>(cascadeIndex * sizeof(float4x4));
    float4 lightPos = mul(float4(P, 1), lightViewProjection);
    lightPos.xyz /= lightPos.w;
    float2 uv = ClipToUV(lightPos.xy);

    const float dilation = 2.0f;
    float d1 = dilation * invShadowSize * 0.125f;
    float d2 = dilation * invShadowSize * 0.875f;
    float d3 = dilation * invShadowSize * 0.625f;
    float d4 = dilation * invShadowSize * 0.375f;
    float result = 1.0f;

    if (NonUniformResourceIndex(cascadeIndex) == 0)
    {
        result = (2.0f * shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv, lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d2, d1), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d1, -d2), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d2, -d1), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d1, d2), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d4, d3), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d3, -d4), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d4, -d3), lightPos.z) +
                  shadowDepth0.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d3, d4), lightPos.z)) /
                 10.0f;
    }
    else if (NonUniformResourceIndex(cascadeIndex) == 1)
    {
        result = (2.0f * shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv, lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d2, d1), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d1, -d2), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d2, -d1), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d1, d2), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d4, d3), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d3, -d4), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d4, -d3), lightPos.z) +
                  shadowDepth1.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d3, d4), lightPos.z)) /
                 10.0f;
    }
    else if (NonUniformResourceIndex(cascadeIndex) == 2)
    {
        result = (2.0f * shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv, lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d2, d1), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d1, -d2), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d2, -d1), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d1, d2), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d4, d3), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d3, -d4), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d4, -d3), lightPos.z) +
                  shadowDepth2.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d3, d4), lightPos.z)) /
                 10.0f;
    }
    else if (NonUniformResourceIndex(cascadeIndex) == 3)
    {
        result = (2.0f * shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv, lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d2, d1), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d1, -d2), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d2, -d1), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d1, d2), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d4, d3), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(-d3, -d4), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d4, -d3), lightPos.z) +
                  shadowDepth3.SampleCmpLevelZero(g_linear_clamp_cmp_greater_sampler, uv + float2(d3, d4), lightPos.z)) /
                 10.0f;
    }

    return result * result;
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

    const float3 P = WorldPositionFromDepth(Input.UV, depth, g_inv_proj_view_mat);
    const float3 V = normalize(g_cam_pos.xyz - P);
    float3 viewPos = ViewPositionFromDepth(Input.UV, depth, g_inv_proj_mat);
    float linearDepth = viewPos.z;
    // TODO
    // float dither = InterleavedGradientNoise(positionCS.xy);
    const uint cascadeIndex = GetSunShadowMapIndex(linearDepth /*, dither */);
    float attenuation = 1.0f;
    if (distance(P, g_cam_pos.xyz) < g_cascade_depths.w)
    {
        attenuation = Shadow3x3PCF(P, cascadeIndex, g_shadow_resolution_inverse.x);
    }

#if 0
    {
        const float4 cascadeColors[4] = {
            float4(0.0, 1.0, 0.0, 1.0),
            float4(0.0, 1.0, 1.0, 1.0),
            float4(0.0, 0.0, 1.0, 1.0),
            float4(1.0, 0.0, 0.0, 1.0)};
        return cascadeColors[cascadeIndex];
    }
#endif

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
        Lo += ShadeLight(light, surfaceInfo, attenuation);
    }

    // Simple depth-based fog
    float view_distance = length(g_cam_pos.xyz - P.xyz);
    float fog_factor = exp(-g_fog_density * view_distance);
    Lo = lerp(g_fog_color, Lo, saturate(fog_factor));

    RETURN(float4(Lo, 1.0f));
}
