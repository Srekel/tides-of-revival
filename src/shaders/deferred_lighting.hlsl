#include "lighting.hlsli"

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

    float3 normal = normalize(unpackNormal(gbuffer_1_sample.xyz));

    if (gbuffer_0_sample.a > 0)
    {
        float3 position = getPositionFromDepth(depth, uv, cbv_frame_const.view_projection_inverted);
        float3 view = normalize(cbv_frame_const.camera_position - position);

        float3 albedo = gbuffer_0_sample.rgb;
        float metallic = gbuffer_2_sample.g;
        float3 f0 = float3(0.04, 0.04, 0.04);

        float3 diffuseColor = albedo * (float3(1.0, 1.0, 1.0) - f0) * (1.0 - metallic);
        float3 specularColor = lerp(f0, albedo, metallic);

        float perceptualRoughness = saturate(gbuffer_2_sample.r);
        float alphaRoughness = perceptualRoughness * perceptualRoughness;

        float3 specularEnvironmentR0 = specularColor;
        float reflectance = max(max(specularColor.r, specularColor.g), specularColor.b);
        float3 specularEnvironmentR90 = float3(1.0, 1.0, 1.0) * clamp(reflectance * 50.0, 0.0, 1.0);

        MaterialInfo materialInfo = {
            perceptualRoughness,
            specularEnvironmentR0,
            alphaRoughness,
            diffuseColor,
            specularEnvironmentR90,
            specularColor
        };

        float3 color = float3(0.0, 0.0, 0.0);

        // TODO(gmodarelli): Use a buffer of main lights
        // Main Light
        {
            DirectionalLight light = {
                cbv_scene_const.main_light_direction,
                cbv_scene_const.main_light_color,
                cbv_scene_const.main_light_intensity,
            };

            color += applyDirectionalLight(light, materialInfo, normal, view);
        }

        // Point Lights
        ByteAddressBuffer point_lights_buffer = ResourceDescriptorHeap[cbv_scene_const.point_lights_buffer_index];
        for (uint i = 0; i < cbv_scene_const.point_lights_count; i++)
        {
            PointLight light = point_lights_buffer.Load<PointLight>(i * sizeof(PointLight));
            color += applyPointLight(light, materialInfo, normal, position, view);
        }

        // IBL Ambient Light
        {
            TextureCube diffuseCube = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];
            TextureCube specularCube = ResourceDescriptorHeap[cbv_scene_const.prefiltered_env_texture_index];
            Texture2D brdfTexture = ResourceDescriptorHeap[cbv_scene_const.brdf_integration_texture_index];
            float mipCount = cbv_scene_const.prefiltered_env_texture_max_lods;
            color += getIBLContribution(
                materialInfo,
                normal,
                view,
                mipCount,
                diffuseCube,
                specularCube,
                brdfTexture,
                sam_bilinear_clamp
            ) * cbv_scene_const.ambient_light_intensity;
        }

        hdr_texture[dispatch_id.xy] = float4(max(hdr_texture[dispatch_id.xy].rgb, color), 1.0);
    }
    else
    {
        TextureCube environment_texture = ResourceDescriptorHeap[cbv_scene_const.env_texture_index];
        float3 env = environment_texture.SampleLevel(sam_bilinear_clamp, normal, 0).rgb;
        // env = clamp(env, 0, 32767.0f);
        hdr_texture[dispatch_id.xy] = float4(max(hdr_texture[dispatch_id.xy].rgb, env), 1.0);
    }
}