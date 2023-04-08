#include "common.hlsli"
#include "pbr.hlsli"
#include "gbuffer.hlsli"

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "CBV(b2), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), "

ConstantBuffer<RenderTargetsConst> cbv_render_targets_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);
ConstantBuffer<SceneConst> cbv_scene_const : register(b2);

SamplerState sam_aniso_clamp : register(s0);

[RootSignature(root_signature)]
[numthreads(8, 8, 1)]
void csDeferredLighting(uint3 dispatch_id : SV_DispatchThreadID) {
    float width, height;
    RWTexture2D<float4> hdr_texture = ResourceDescriptorHeap[cbv_render_targets_const.hdr_texture_index];
    hdr_texture.GetDimensions(width, height);

    if (dispatch_id.x > width || dispatch_id.y > height) return;

    float2 uv = (dispatch_id.xy + 0.5f) / float2(width, height);

    // Sample Depth
    Texture2D depth_texture = ResourceDescriptorHeap[cbv_render_targets_const.depth_texture_index];
    float depth = depth_texture.SampleLevel(sam_aniso_clamp, uv, 0).r;

    // Derive world position from depth
    float3 position_ws = 0;
    {
        float x          = uv.x * 2.0f - 1.0f;
        float y          = (1.0f - uv.y) * 2.0f - 1.0f;
        float4 pos_clip  = float4(x, y, depth, 1.0f);
        float4 pos_world = mul(pos_clip, cbv_frame_const.view_projection_inverted);
        position_ws = pos_world.xyz / pos_world.w;
    }

    // Decode buffer information
    Texture2D gbuffer_0 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_0_index];
    Texture2D gbuffer_1 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_1_index];
    Texture2D gbuffer_2 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_2_index];

    const float3 v = normalize(cbv_frame_const.camera_position - position_ws);
    float3 base_color = gbuffer_0.SampleLevel(sam_aniso_clamp, uv, 0).rgb;
    float3 n = gbuffer_1.SampleLevel(sam_aniso_clamp, uv, 0).rgb;
    float4 material = gbuffer_2.SampleLevel(sam_aniso_clamp, uv, 0);

    TextureCube<float3> ibl_radiance_texture = ResourceDescriptorHeap[cbv_scene_const.radiance_texture_index];
    TextureCube<float3> ibl_irradiance_texture = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];

    float3 lightDirection[3] = {
        float3(0.0, 1.0, 0.0),
        float3(0.0, 1.0, 0.0),
        float3(0.0, 1.0, 0.0),
    };
    float3 lightColor[3] = {
        float3(1.0, 0.953, 0.945),
        float3(1.0, 0.953, 0.945),
        float3(1.0, 0.953, 0.945),
    };

    float3 color = LightSurface(v, n, 1, lightColor, lightDirection, base_color, material.r, material.g, material.a, ibl_radiance_texture, ibl_irradiance_texture, sam_aniso_clamp, 10);

    hdr_texture[dispatch_id.xy] = float4(color, 1.0);
}
