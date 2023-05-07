#include "common.hlsli"
#include "pbr.hlsli"
#include "gbuffer.hlsli"

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "CBV(b2), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s1, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

ConstantBuffer<RenderTargetsConst> cbv_render_targets_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);
ConstantBuffer<SceneConst> cbv_scene_const : register(b2);

SamplerState sam_aniso_clamp : register(s0);
SamplerState sam_bilinear_clamp : register(s1);

[RootSignature(root_signature)]
[numthreads(8, 8, 1)]
void csLightingComposition(uint3 dispatch_id : SV_DispatchThreadID) {
    float width, height;
    RWTexture2D<float4> hdr_texture = ResourceDescriptorHeap[cbv_render_targets_const.hdr_texture_index];
    hdr_texture.GetDimensions(width, height);

    if (dispatch_id.x > width || dispatch_id.y > height) return;

    float2 uv = (dispatch_id.xy + 0.5f) / float2(width, height);

    Texture2D gbuffer_0 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_0_index];
    Texture2D gbuffer_1 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_1_index];
    Texture2D gbuffer_2 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_2_index];
    Texture2D depth_texture = ResourceDescriptorHeap[cbv_render_targets_const.depth_texture_index];
    Texture2D light_diffuse_texture = ResourceDescriptorHeap[cbv_render_targets_const.light_diffuse_texture_index];
    Texture2D light_specular_texture = ResourceDescriptorHeap[cbv_render_targets_const.light_specular_texture_index];
    TextureCube environment_texture = ResourceDescriptorHeap[cbv_scene_const.radiance_texture_index];

    float depth = depth_texture.SampleLevel(sam_aniso_clamp, uv, 0).r;
    float3 position = getPositionFromDepth(depth, uv, cbv_frame_const.view_projection_inverted);
    float3 camera_to_pixel = position - cbv_frame_const.camera_position;

    float4 gbuffer_0_sample = gbuffer_0.SampleLevel(sam_aniso_clamp, uv, 0);
    float4 gbuffer_1_sample = gbuffer_1.SampleLevel(sam_aniso_clamp, uv, 0);
    float4 gbuffer_2_sample = gbuffer_2.SampleLevel(sam_aniso_clamp, uv, 0);

    float4 color = float4(0.0, 0.0, 0.0, 1.0);

    if (gbuffer_0_sample.a > 0)
    {
        // Light - Diffuse and Specular.
        float3 light_diffuse  = light_diffuse_texture.SampleLevel(sam_aniso_clamp, uv, 0).rgb;
        float3 light_specular = light_specular_texture.SampleLevel(sam_aniso_clamp, uv, 0).rgb;

        // Compose everything
        color.rgb += light_diffuse * gbuffer_0_sample.rgb + light_specular;
    }
    else
    {
        float3 normal = gbuffer_1_sample.xyz;
        color.rgb += environment_texture.SampleLevel(sam_bilinear_clamp, normal, 0).rgb;
    }

    hdr_texture[dispatch_id.xy] = saturate_16(color);
}