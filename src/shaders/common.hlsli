#ifndef __COMMON_HLSL__
#define __COMMON_HLSL__

// TMP
#define MAX_LIGHTS 32
#define GAMMA 2.2
#define INVALID_TEXTURE_INDEX 0xFFFFFFFF

#define per_object_space   space0
#define per_material_space space1
#define per_pass_space     space2
#define per_frame_space    space3

struct FrameConst {
    float4x4 world_to_clip;
    float4x4 view_projection_inverted;
    float3 camera_position;
    float time;
    uint padding1;
    uint padding2;
    uint padding3;
    uint light_count;
    float4 light_positions[MAX_LIGHTS];
    float4 light_radiances[MAX_LIGHTS];
};

struct SceneConst {
    uint radiance_texture_index;
    uint irradiance_texture_index;
    uint specular_texture_index;
    uint brdf_integration_texture_index;
};

bool has_valid_texture(uint texture_index) { return texture_index != INVALID_TEXTURE_INDEX; }

float3 gamma(float3 color) { return pow(color, 1.0f / GAMMA); }
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

/*------------------------------------------------------------------------------
    LUMINANCE
------------------------------------------------------------------------------*/
static const float3 lumCoeff = float3(0.299f, 0.587f, 0.114f);

float luminance(float3 color)
{
    return max(dot(color, lumCoeff), 0.0001f);
}

float luminance(float4 color)
{
    return max(dot(color.rgb, lumCoeff), 0.0001f);
}

#endif // __COMMON_HLSL__