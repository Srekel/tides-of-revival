#ifndef __COMMON_HLSL__
#define __COMMON_HLSL__

#include "constants.hlsli"

struct Vertex {
    float3 position;
    float3 normal;
    float2 uv;
    float4 tangent;
    float4 color;
};

struct DirectionalLight {
    float3 direction;
    float3 color;
    float intensity;
};

struct PointLight {
    float3 position;
    float range;
    float3 color;
    float intensity;
};

struct FrameConst {
    float4x4 view_projection;
    float4x4 view_projection_inverted;
    float3 camera_position;
};

struct SceneConst {
    float3 main_light_direction;
    uint point_lights_buffer_index;
    float3 main_light_color;
    uint point_lights_count;
    float main_light_intensity;
    float prefiltered_env_texture_max_lods;
    uint env_texture_index;
    uint irradiance_texture_index;
    uint prefiltered_env_texture_index;
    uint brdf_integration_texture_index;
    float ambient_light_intensity;
    float _padding;
};

struct FullscreenTriangleOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

struct RenderTargetsConst {
    uint gbuffer_0_index;
    uint gbuffer_1_index;
    uint gbuffer_2_index;
    uint depth_texture_index;
    uint scene_color_texture_index;
};

struct GBufferTargets {
    float4 albedo : SV_Target0;         // R8B8G8A8_UNORM
    float4 normal : SV_Target1;         // R10G10B10A2_UNORM
    float4 material : SV_Target2;       // R8G8B8A8_UNORM
    float4 scene_color : SV_Target3;    // R16G16B16A16_FLOAT
};

struct MaterialInfo
{
    float perceptualRoughness;      // roughness value as authored by the model creator (input to shader)
    float3 reflectance0;            // full reflectance color (normal incidence angle)
    float alphaRoughness;           // roughness mapped to a more linear change in the roughness
    float3 diffuseColor;            // color contribution from diffuse lighting
    float3 reflectace90;            // reflectance color at grazing angle
    float3 specularColor;           // color contribution from specular lighting
};

struct AngularInfo
{
    float NdotL;                    // cos angle between normal and light direction
    float NdotV;                    // cos angle between normal and view direction
    float NdotH;                    // cos angle between normal and half vector
    float LdotH;                    // cos angle between light direction and half vector
    float VdotH;                    // cos angle between view direction and half vector
};

AngularInfo getAngularInfo(float3 pointToLight, float3 normal, float3 view) {
    float3 n = normalize(normal);           // outward direction of surface point
    float3 v = normalize(view);             // direction from surface point to view
    float3 l = normalize(pointToLight);     // direction from surface point to light
    float3 h = normalize(l + v);            // direction of the vector between l and v

    float NdotL = clamp(dot(n, l), 0.0, 1.0);
    float NdotV = clamp(dot(n, v), 0.0, 1.0);
    float NdotH = clamp(dot(n, h), 0.0, 1.0);
    float LdotH = clamp(dot(l, h), 0.0, 1.0);
    float VdotH = clamp(dot(v, h), 0.0, 1.0);

    AngularInfo angularInfo = {
        NdotL,
        NdotV,
        NdotH,
        LdotH,
        VdotH
    };

    return angularInfo;
}


float3 packNormal(float3 normal) {
    return (normal + 1.0) * 0.5;
}

float3 unpackNormal(float3 normal) {
    return normal * 2.0 - 1.0;
}

bool has_valid_texture(uint texture_index) { return texture_index != INVALID_TEXTURE_INDEX; }

float3 gamma(float3 color) { return pow(abs(color), 1.0f / GAMMA); }
float3 degamma(float3 color) { return pow(color, GAMMA); }

float3 unpack(float3 value) { return value * 2.0f - 1.0f; }
float3 pack(float3 value) { return value * 0.5f + 0.5f; }

float3x3 makeTBN(float3 n, float3 t)
{
    // re-orthogonalize T with respect to N
    t = normalize(t - dot(t, n) * n);
    // compute bitangent
    float3 b = cross(n, t);
    // create matrix
    return float3x3(t, b, n);
}

float3 getPositionFromDepth(float depth, float2 uv, float4x4 view_projection_inverted)
{
    float x = uv.x * 2.0f - 1.0f;
    float y = (1.0f - uv.y) * 2.0f - 1.0f;
    float4 position_cs = float4(x, y, depth, 1.0f);
    float4 position_ws = mul(position_cs, view_projection_inverted);
    return position_ws.xyz / position_ws.w;
}

#endif // __COMMON_HLSL__