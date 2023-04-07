#ifndef __COMMON_HLSL__
#define __COMMON_HLSL__

// TMP
#define MAX_LIGHTS 32
#define GAMMA 2.2

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

float3 gammaCorrect(float3 color) {
    float gamma = 1.0 / GAMMA;
    color = pow(color, float3(gamma, gamma, gamma));
    return color;
}

#endif // __COMMON_HLSL__