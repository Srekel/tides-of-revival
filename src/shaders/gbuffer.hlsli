#ifndef __GBUFFER_HLSL__
#define __GBUFFER_HLSL__

struct RenderTargetsConst {
    uint gbuffer_0_index;
    uint gbuffer_1_index;
    uint gbuffer_2_index;
    uint depth_texture_index;
    uint light_diffuse_texture_index;
    uint light_specular_texture_index;
    uint hdr_texture_index;
};

struct GBufferTargets {
    float4 albedo : SV_Target0;         // R8B8G8A8_UNORM
    float4 normal : SV_Target1;         // R10G10B10A2_UNORM
    float4 material : SV_Target2;       // R8G8B8A8_UNORM

    void encode_albedo(float3 input_albedo) {
        albedo = float4(input_albedo, 1.0);
    }

    void encode_normals(float3 input_normal) {
        normal = float4(input_normal * 0.5 + 0.5, 0.0);
    }

    void encode_material(float roughness, float metallic, float occlusion, float emissive) {
        material.r = roughness;
        material.g = metallic;
        material.b = emissive;
        material.a = occlusion;
    }
};

#endif // __GBUFFER_HLSL__