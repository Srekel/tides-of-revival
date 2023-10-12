#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

SamplerState sam_aniso_clamp : register(s0);

struct DrawConst {
    float3 fog_color;
    float fog_radius;
    float fog_fade_rate;
    float fog_density;
    uint scene_color_texture_index;
    uint depth_texture_index;
    uint gbuffer_0_texture_index;
    float3 _padding;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);

[RootSignature(ROOT_SIGNATURE)]
FullscreenTriangleOutput vsFullscreenTriangle(uint vertexID : SV_VertexID)
{
    FullscreenTriangleOutput output;

    output.uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.position = float4(output.uv * float2(2, -2) + float2(-1, 1), 0, 1);

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
float4 psDepthBasedFog(FullscreenTriangleOutput input) : SV_Target
{
    Texture2D scene_color_texture = ResourceDescriptorHeap[cbv_draw_const.scene_color_texture_index];
    Texture2D depth_texture = ResourceDescriptorHeap[cbv_draw_const.depth_texture_index];
    Texture2D gbuffer_0 = ResourceDescriptorHeap[cbv_draw_const.gbuffer_0_texture_index];
    float skybox_mask = gbuffer_0.Sample(sam_aniso_clamp, input.uv).a;

    float3 scene_color = scene_color_texture.Sample(sam_aniso_clamp, input.uv).rgb;
    float scene_depth = depth_texture.Sample(sam_aniso_clamp, input.uv).r;

    float3 position = getPositionFromDepth(scene_depth, input.uv, cbv_frame_const.view_projection_inverted);
    float distance_from_camera = length(cbv_frame_const.camera_position - position) - cbv_draw_const.fog_radius;
    float distance_factor = max(0.0f, distance_from_camera) / cbv_draw_const.fog_radius;
    float fog_factor = 1.0f - exp(-cbv_draw_const.fog_fade_rate * distance_factor);
    fog_factor *= skybox_mask;

    float3 color = lerp(scene_color, cbv_draw_const.fog_color, fog_factor);
    return float4(color, 1.0);
}
