#ifndef __COMMON_HLSL__
#define __COMMON_HLSL__

// TMP
#define MAX_LIGHTS 32

static const float GAMMA = 2.2;
static const uint INVALID_TEXTURE_INDEX = 0xFFFFFFFF;

static const float FLT_MIN             = 0.00000001f;
static const float FLT_MAX_11          = 1023.0f;
static const float FLT_MAX_16          = 32767.0f;

static const float PI = 3.14159265f;
static const float INV_PI = 1.0f / PI;
static const float EPSILON = 1e-6f;

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
    uint brdf_integration_texture_index;
};

struct FullscreenTriangleOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
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

float3 getPositionFromDepth(float depth, float2 uv, float4x4 view_projection_inverted)
{
    float x = uv.x * 2.0f - 1.0f;
    float y = (1.0f - uv.y) * 2.0f - 1.0f;
    float4 position_cs = float4(x, y, depth, 1.0f);
    float4 position_ws = mul(position_cs, view_projection_inverted);
    return position_ws.xyz / position_ws.w;
}

// From Sebastien Lagarde Moving Frostbite to PBR page 69
float3 get_dominant_specular_direction(float3 normal, float3 reflection, float roughness)
{
    const float smoothness = 1.0f - roughness;
    const float alpha = smoothness * (sqrt(smoothness) + roughness);
    
    return lerp(normal, reflection, alpha);
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

/*------------------------------------------------------------------------------
    SATURATE
------------------------------------------------------------------------------*/
float  saturate_11(float x)  { return clamp(x, 0.0f, FLT_MAX_11); }
float2 saturate_11(float2 x) { return clamp(x, 0.0f, FLT_MAX_11); }
float3 saturate_11(float3 x) { return clamp(x, 0.0f, FLT_MAX_11); }
float4 saturate_11(float4 x) { return clamp(x, 0.0f, FLT_MAX_11); }

float  saturate_16(float x)  { return clamp(x, 0.0f, FLT_MAX_16); }
float2 saturate_16(float2 x) { return clamp(x, 0.0f, FLT_MAX_16); }
float3 saturate_16(float3 x) { return clamp(x, 0.0f, FLT_MAX_16); }
float4 saturate_16(float4 x) { return clamp(x, 0.0f, FLT_MAX_16); }

#endif // __COMMON_HLSL__