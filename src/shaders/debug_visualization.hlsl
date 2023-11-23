#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "CBV(b2), " \
    "CBV(b3), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s1, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

struct DrawConst {
    uint view_mode;
};

ConstantBuffer<RenderTargetsConst> cbv_render_targets_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);
ConstantBuffer<SceneConst> cbv_scene_const : register(b2);
ConstantBuffer<DrawConst> cbv_draw_const : register(b3);

SamplerState sam_aniso_clamp : register(s0);
SamplerState sam_bilinear_clamp : register(s1);

[RootSignature(ROOT_SIGNATURE)]
FullscreenTriangleOutput vsFullscreenTriangle(uint vertexID : SV_VertexID)
{
    FullscreenTriangleOutput output;

    output.uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.position = float4(output.uv * float2(2, -2) + float2(-1, 1), 0, 1);

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
float4 psDebugVisualization(FullscreenTriangleOutput input) : SV_Target
{
    float2 uv = input.uv;

    // Sample Depth
    // ============
    Texture2D depth_texture = ResourceDescriptorHeap[cbv_render_targets_const.depth_texture_index];
    float depth = depth_texture.SampleLevel(sam_aniso_clamp, uv, 0).r;

    // Sample GBuffer
    // ==============
    Texture2D gbuffer_0 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_0_index];
    Texture2D gbuffer_1 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_1_index];
    Texture2D gbuffer_2 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_2_index];

    float4 gbuffer_0_sample = gbuffer_0.SampleLevel(sam_aniso_clamp, uv, 0);
    float4 gbuffer_1_sample = gbuffer_1.SampleLevel(sam_aniso_clamp, uv, 0);
    float4 gbuffer_2_sample = gbuffer_2.SampleLevel(sam_aniso_clamp, uv, 0);

    float3 normal = normalize(unpackNormal(gbuffer_1_sample.xyz));
    float3 color = float3(0, 0, 0);

    if (cbv_draw_const.view_mode == 1)             // Albedo
    {
        color = gbuffer_0_sample.rgb;
    }
    else if (cbv_draw_const.view_mode == 2)        // World Normals
    {
        color = normal.rgb * 0.5 + 0.5;
    }
    else if (cbv_draw_const.view_mode == 3)        // Metallic
    {
        color = gbuffer_2_sample.ggg;
    }
    else if (cbv_draw_const.view_mode == 4)        // Roughness
    {
        float perceptualRoughness = saturate(gbuffer_2_sample.r);
        float alphaRoughness = perceptualRoughness * perceptualRoughness;
        color = float3(alphaRoughness, alphaRoughness, alphaRoughness);
    }
    else if (cbv_draw_const.view_mode == 5)        // Ambient Occlusion
    {
        color = gbuffer_2_sample.aaa;
    }
    else if (cbv_draw_const.view_mode == 6)        // Depth
    {
        color = float3(depth, depth, depth);
    }

    return float4(gamma(color), 1.0);
}