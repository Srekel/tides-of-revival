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
    RWTexture2D<float4> light_diffuse_texture = ResourceDescriptorHeap[cbv_render_targets_const.light_diffuse_texture_index];
    RWTexture2D<float4> light_specular_texture = ResourceDescriptorHeap[cbv_render_targets_const.light_specular_texture_index];
    light_diffuse_texture.GetDimensions(width, height);

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

    // Build surface information
    // =========================
    float3 position = getPositionFromDepth(depth, uv, cbv_frame_const.view_projection_inverted);
    float3 camera_to_pixel = position - cbv_frame_const.camera_position;
    float camera_to_pixel_length = length(camera_to_pixel);
    camera_to_pixel = normalize(camera_to_pixel);

    float3 albedo = gbuffer_0_sample.rgb;
    float3 normal = gbuffer_1_sample.xyz;
    float roughness = gbuffer_2_sample.r;
    float roughness_alpha = roughness * roughness;
    float roughness_alpha_squared = roughness_alpha * roughness_alpha;
    float metallic = gbuffer_2_sample.g;
    float occlusion = gbuffer_2_sample.a;
    float emission = gbuffer_2_sample.b;
    float3 F0 = lerp(0.04f, albedo, metallic);

    // Light information
    // =================
    // NOTE(gmodarelli): Hardcoding a directional light (sun)
    float3 light_color = float3(1.0, 1.0, 1.0);
    float light_intensity = 10.0;
    float3 light_direction = float3(0.0, 1.0, 0.0);
    // TODO(gmodarelli): This turns everything to black
    // float light_attenuation = 1.0;// saturate(dot(-light_direction, float3(0.0, 1.0, 0.0)));
    float light_attenuation = saturate(dot(light_direction, float3(0.0, 1.0, 0.0)));
    float3 light_radiance = light_color * light_intensity * light_attenuation * saturate(dot(normal, -light_direction));

    // Angular information
    // ===================
    float3 n = normalize(normal);
    float3 v = (-camera_to_pixel);
    float3 l = normalize(-light_direction);
    float3 h = normalize(l + v);

    float n_dot_l = saturate(dot(n, l));
    float n_dot_v = saturate(dot(n, v));
    float n_dot_h = saturate(dot(n, h));
    float l_dot_h = saturate(dot(l, h));
    float v_dot_h = saturate(dot(v, h));

    float3 light_specular = 0.0f;
    float3 light_diffuse = 0.0f;
    float3 specular_energy = 1.0;
    float3 diffuse_energy = 1.0;
    if (gbuffer_0_sample.a > 0)
    {
        light_specular += BRDF_Specular_Isotropic(roughness_alpha, roughness_alpha_squared, F0, metallic, n_dot_v, n_dot_l, n_dot_h, v_dot_h, diffuse_energy, specular_energy);
        light_diffuse += BRDF_Diffuse_OrenNayar(albedo, roughness, roughness_alpha_squared, v_dot_h, n_dot_l, n_dot_v);
        light_diffuse *= diffuse_energy;
    }

    float3 emissive = emission * albedo;

    light_diffuse_texture[dispatch_id.xy] = float4(saturate_11(light_diffuse * light_radiance + emissive), 1.0);
    light_specular_texture[dispatch_id.xy] = float4(saturate_11(light_specular * light_radiance), 1.0);
}
