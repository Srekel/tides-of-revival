#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"
#include "utils.hlsl"

RES(SamplerState, g_linear_repeat_sampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, g_linear_clamp_edge_sampler, UPDATE_FREQ_NONE, s1, binding = 2);
RES(SamplerState, g_point_repeat_sampler, UPDATE_FREQ_NONE, s2, binding = 3);

RES(Tex2D(float2), g_brdf_integration_map, UPDATE_FREQ_NONE, t0, binding = 4);
RES(TexCube(float4), g_irradiance_map, UPDATE_FREQ_NONE, t1, binding = 5);
RES(TexCube(float4), g_specular_map, UPDATE_FREQ_NONE, t2, binding = 6);

RES(Tex2D(float4), gBuffer0, UPDATE_FREQ_NONE, t3, binding = 7);
RES(Tex2D(float4), gBuffer1, UPDATE_FREQ_NONE, t4, binding = 8);
RES(Tex2D(float4), gBuffer2, UPDATE_FREQ_NONE, t5, binding = 9);
RES(Tex2D(float), depthBuffer, UPDATE_FREQ_NONE, t6, binding = 10);
RES(Tex2D(float), shadowDepthBuffer, UPDATE_FREQ_NONE, t7, binding = 11);

#define BRDF_FUNCTION FILAMENT_BRDF
#include "pbr.hlsl"

cbuffer cbFrame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_proj_view_mat;
    float4x4 g_inv_proj_view_mat;
    float4x4 g_light_proj_view;
    float4x4 g_inv_light_proj_view_mat;
    float4 g_cam_pos;
    uint g_directional_lights_buffer_index;
    uint g_point_lights_buffer_index;
    uint g_directional_lights_count;
    uint g_point_lights_count;
    float g_apply_shadows;
    float g_environment_light_intensity;
    float2 _padding;
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

float ShadowFetch(Texture2D<float> shadowMap, float2 uv, int2 offset, float depth)
{
    return step(depth, SampleLvlOffsetTex2D(shadowMap, Get(g_point_repeat_sampler), uv, 0, offset).r);
}

float ShadowFetchBilinear(Texture2D<float> shadowMap, float2 uv, float2 uvFrac, int2 offset, float depth)
{
    float4 s = float4(
        ShadowFetch(shadowMap, uv, offset + int2(0, 0), depth),
        ShadowFetch(shadowMap, uv, offset + int2(1, 0), depth),
        ShadowFetch(shadowMap, uv, offset + int2(0, 1), depth),
        ShadowFetch(shadowMap, uv, offset + int2(1, 1), depth));

    float a = lerp(s.x, s.y, uvFrac.x);
    float b = lerp(s.z, s.w, uvFrac.x);
    return lerp(a, b, uvFrac.y);
}

float ShadowTest(float4 Pl, float2 shadowMapDimensions)
{
    // homogenous position after perspective divide
    const float3 projLSpaceCoords = Pl.xyz / Pl.w;

    // light frustum check
    if (projLSpaceCoords.x < -1.0f || projLSpaceCoords.x > 1.0f ||
        projLSpaceCoords.y < -1.0f || projLSpaceCoords.y > 1.0f ||
        projLSpaceCoords.z < 0.0f || projLSpaceCoords.z > 1.0f)
    {
        return 1.0f;
    }

    const float2 texelSize = 1.0f / (shadowMapDimensions);

    // clip space [-1, 1] --> texture space [0, 1]
    const float2 shadowTexCoords = float2(0.5f, 0.5f) + projLSpaceCoords.xy * float2(0.5f, -0.5f); // invert Y

    // const float BIAS = pcfTestLightData.depthBias * tan(acos(pcfTestLightData.NdotL));
    const float BIAS = 0.0001f;
    const float pxDepthInLSpace = projLSpaceCoords.z;

    float shadow = 0.0f;
    float2 shadowUVFrac = frac(shadowTexCoords * shadowMapDimensions);

#define USE_PCF
#ifdef USE_PCF

    // PCF
    const int rowHalfSize = 2;
    [[unroll]] for (int x = -rowHalfSize; x <= rowHalfSize; ++x)
    {
        [[unroll]] for (int y = -rowHalfSize; y <= rowHalfSize; ++y)
        {
            shadow += ShadowFetchBilinear(Get(shadowDepthBuffer), shadowTexCoords, shadowUVFrac, int2(x, y), pxDepthInLSpace);
        }
    }
    shadow /= (rowHalfSize * 2 + 1) * (rowHalfSize * 2 + 1);

#else

    shadow += ShadowFetchBilinear(Get(shadowDepthBuffer), shadowTexCoords, shadowUVFrac, int2(0, 0), pxDepthInLSpace);

#endif

    return 1.0 - shadow;
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

    float4 positionLightSpace = mul(g_light_proj_view, float4(P, 1.0f));
    float shadowAttenuation = 1.0f;
    if (g_apply_shadows)
    {
        shadowAttenuation = ShadowTest(positionLightSpace, 2048.0f);
    }

    float reflectance = pbrSample.a;
    float metalness = pbrSample.b;
    float roughness = pbrSample.g;
    if (roughness < 0.04)
        roughness = 0.04;

    float3 Lo = float3(0.0f, 0.0f, 0.0f);

    // Point Lights
    ByteAddressBuffer pointLightsBuffer = ResourceDescriptorHeap[g_point_lights_buffer_index];
    for (uint i = 0; i < g_point_lights_count; ++i)
    {
        const PointLight pointLight = pointLightsBuffer.Load<PointLight>(i * sizeof(PointLight));
        const float3 Pl = pointLight.positionAndRadius.xyz;
        const float radius = pointLight.positionAndRadius.w;
        const float3 L = normalize(Pl - P);
        const float NdotL = max(dot(N, L), 0.0f);
        const float distance = length(Pl - P);
        const float distanceByRadius = 1.0f - pow((distance / radius), 4);
        const float clamped = pow(saturate(distanceByRadius), 2.0f);
        const float attenuation = clamped / (distance * distance + 1.0f);

        const float3 color = sRGBToLinear_Float3(pointLight.colorAndIntensity.rgb);
        const float intensity = pointLight.colorAndIntensity.a;
        const float3 radiance = color * intensity * attenuation;

#if BRDF_FUNCTION == FILAMENT_BRDF
        const float3 brdf = FilamentBRDF(N, V, L, baseColor.rgb, roughness, metalness, reflectance);
#else
        const float3 brdf = BRDF(N, V, L, baseColor.rgb, roughness, metalness);
#endif
        Lo += brdf * radiance * NdotL * shadowAttenuation;
    }

    // Directional Lights
    ByteAddressBuffer directionalLightsBuffer = ResourceDescriptorHeap[g_directional_lights_buffer_index];
    for (uint i = 0; i < g_directional_lights_count; ++i)
    {
        const DirectionalLight directionalLight = directionalLightsBuffer.Load<DirectionalLight>(i * sizeof(DirectionalLight));
        const float3 L = directionalLight.directionAndShadowMap.xyz;
        const float NdotL = max(dot(N, L), 0.0f);
        const float3 color = sRGBToLinear_Float3(directionalLight.colorAndIntensity.rgb);
        const float intensity = directionalLight.colorAndIntensity.a;
        const float3 radiance = color * intensity;

#if BRDF_FUNCTION == FILAMENT_BRDF
        // TODO: Specify reflectance per material
        const float3 brdf = FilamentBRDF(N, V, L, baseColor.rgb, roughness, metalness, reflectance);
#else
        const float3 brdf = BRDF(N, V, L, baseColor.rgb, roughness, metalness);
#endif
        Lo += brdf * radiance * NdotL * shadowAttenuation;
    }

    // IBL (Environment Light)
    if (g_environment_light_intensity >= 0.0f)
    {
        Lo += EnvironmentBRDF(N, V, baseColor.rgb, roughness, metalness) * g_environment_light_intensity;
    }

    // Simple depth-based fog
    float view_distance = length(g_cam_pos.xyz - P.xyz);
    float fog_factor = exp(-g_fog_density * view_distance);
    Lo = lerp(g_fog_color, Lo, saturate(fog_factor));

    RETURN(float4(Lo, 1.0f));
}
