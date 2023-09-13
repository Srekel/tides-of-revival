#ifndef __COMMON_HLSL__
#define __COMMON_HLSL__

// TMP
#define MAX_LIGHTS 32

static const float GAMMA = 2.2;
static const uint INVALID_TEXTURE_INDEX = 0xFFFFFFFF;

#define per_object_space   space0
#define per_material_space space1
#define per_pass_space     space2
#define per_frame_space    space3

struct DirectionalLight {
    float3 direction;
    float3 radiance;
};

struct PointLight {
    float3 position;
    float3 radiance;
    float radius;
    float falloff;
    float max_intensity;
};


struct FrameConst {
    float4x4 view_projection;
    float4x4 view_projection_inverted;
    float3 camera_position;
};

struct SceneConst {
    float3 main_light_direction;
    uint point_lights_buffer_index;
    float3 main_light_radiance;
    uint point_lights_count;
    uint radiance_texture_index;
    uint irradiance_texture_index;
    uint specular_texture_index;
    uint brdf_integration_texture_index;
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
    uint hdr_texture_index;
};

struct GBufferTargets {
    float4 albedo : SV_Target0;         // R8B8G8A8_UNORM
    float4 normal : SV_Target1;         // R10G10B10A2_UNORM
    float4 material : SV_Target2;       // R8G8B8A8_UNORM
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

#endif // __COMMON_HLSL__