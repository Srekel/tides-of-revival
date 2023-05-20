#include "common.hlsli"

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

#include "pbr.hlsli"

[RootSignature(root_signature)]
[numthreads(8, 8, 1)]
void csDeferredLighting(uint3 dispatch_id : SV_DispatchThreadID) {
    float width, height;
    RWTexture2D<float4> hdr_texture = ResourceDescriptorHeap[cbv_render_targets_const.hdr_texture_index];
    hdr_texture.GetDimensions(width, height);

    if (dispatch_id.x > width || dispatch_id.y > height) return;

    float2 uv = (dispatch_id.xy + 0.5f) / float2(width, height);

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

    if (gbuffer_0_sample.a > 0)
    {
        float3 albedo = gbuffer_0_sample.rgb;
        float3 normal = gbuffer_1_sample.xyz;
        float roughness = gbuffer_2_sample.r;
        float metallic = gbuffer_2_sample.g;
        float occlusion = gbuffer_2_sample.a;
        float3 position = getPositionFromDepth(depth, uv, cbv_frame_const.view_projection_inverted);

        // TODO(gmodarelli): Apply real lights
        float3 lightColor = float3(1.0, 1.0, 1.0);
        float3 lightDirection = normalize(float3(1.0, 1.0, 1.0));
        const float3 V = normalize(cbv_frame_const.camera_position - position);
        float3 color = LightSurface(V, normal, lightDirection, lightColor, albedo, roughness, metallic, occlusion);

        float3 emissive = gbuffer_2_sample.b * albedo;
        hdr_texture[dispatch_id.xy] = float4(color + emissive, 1.0);
    }
    else
    {
        TextureCube environment_texture = ResourceDescriptorHeap[cbv_scene_const.specular_texture_index];
        float3 normal = gbuffer_1_sample.xyz;
        float3 env = environment_texture.SampleLevel(sam_bilinear_clamp, normal, 0).rgb;
        hdr_texture[dispatch_id.xy] = float4(saturate_16(env), 1.0);
    }
}
