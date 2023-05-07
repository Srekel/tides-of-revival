#include "common.hlsli"
#include "gbuffer.hlsli"
#include "pbr.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "CBV(b2), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s1, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

SamplerState sam_aniso_clamp : register(s0);
SamplerState sam_bilinear_clamp : register(s1);

ConstantBuffer<RenderTargetsConst> cbv_render_targets_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);
ConstantBuffer<SceneConst> cbv_scene_const : register(b2);

[RootSignature(ROOT_SIGNATURE)]
FullscreenTriangleOutput vsFullscreenTriangle(uint vertexID : SV_VertexID)
{
    FullscreenTriangleOutput output;

    output.uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.position = float4(output.uv * float2(2, -2) + float2(-1, 1), 0, 1);

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
float4 psImageBasedLighting(FullscreenTriangleOutput input) : SV_Target
{
    float width, height;
    Texture2D gbuffer_0 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_0_index];
    Texture2D gbuffer_1 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_1_index];
    Texture2D gbuffer_2 = ResourceDescriptorHeap[cbv_render_targets_const.gbuffer_2_index];
    Texture2D depth_texture = ResourceDescriptorHeap[cbv_render_targets_const.depth_texture_index];
    TextureCube ibl_radiance_texture = ResourceDescriptorHeap[cbv_scene_const.radiance_texture_index];
    TextureCube ibl_specular_texture = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];
    Texture2D env_brdf_texture = ResourceDescriptorHeap[cbv_scene_const.brdf_integration_texture_index];

    // gbuffer_0.GetDimensions(width, height);
    // float2 uv = input.uv * float2(width, height);
    float2 uv = input.uv;

    // Sample Depth
    // ============
    float depth = depth_texture.SampleLevel(sam_aniso_clamp, uv, 0).r;

    // Sample GBuffer
    // ==============
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

    // Compute specular energy
    const float n_dot_v = saturate(dot(-camera_to_pixel, normal));
    const float3 F = F_Schlick_Roughness(F0, n_dot_v, roughness);
    const float2 envBRDF = env_brdf_texture.SampleLevel(sam_bilinear_clamp, float2(n_dot_v, roughness), 0.0f).xy;
    const float3 specular_energy = F * envBRDF.x + envBRDF.y;

    // IBL - Diffuse
    float3 diffuse_energy = compute_diffuse_energy(specular_energy, metallic);
    // TODO(gmodarelli): missing ambient light factor
    float3 ibl_diffuse = ibl_radiance_texture.SampleLevel(sam_aniso_clamp, normal, 0.0).rgb * albedo * diffuse_energy;
    ibl_diffuse *= gbuffer_0_sample.a;

    // IBL - Specular
    const float3 reflection = reflect(camera_to_pixel, normal);
    float3 dominant_specular_direction = get_dominant_specular_direction(normal, reflection, roughness);
    float mip_level = lerp(0, 8, roughness);
    // TODO(gmodarelli): missing ambient light factor
    float3 ibl_specular = ibl_specular_texture.SampleLevel(sam_aniso_clamp, dominant_specular_direction, mip_level).rgb * specular_energy;
    ibl_specular *= gbuffer_0_sample.a;

    return float4(ibl_diffuse + ibl_specular, 1.0);
}