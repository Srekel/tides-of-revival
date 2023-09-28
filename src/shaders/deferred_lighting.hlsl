#include "common.hlsli"
#include "pbr.hlsli"

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

float calculatePointLightAttenuation(float distance, float radius, float max_intensity, float falloff);

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
        float roughness = gbuffer_2_sample.r;
        float metallic = gbuffer_2_sample.g;
        float3 emissive = gbuffer_2_sample.b * gbuffer_0_sample.rgb;

        ByteAddressBuffer point_lights_buffer = ResourceDescriptorHeap[cbv_scene_const.point_lights_buffer_index];

        float3 Lo = float3(0.0, 0.0, 0.0);

        // Main Directional Light
        {
            float attenuation = 1.0;
            float3 L = cbv_scene_const.main_light_direction;
            Lo += calculateLightContribution(L, cbv_scene_const.main_light_diffuse, attenuation, albedo, normal, roughness, metallic, view);
        }

        // Point Lights
        for (uint i = 0; i < cbv_scene_const.point_lights_count; i++)
        {
            PointLight light = point_lights_buffer.Load<PointLight>(i * sizeof(PointLight));
            float d = distance(light.position, position);
            float attenuation = calculatePointLightAttenuation(d, light.radius, light.max_intensity, light.falloff);
            if (attenuation > 0.0) {
                float3 L = normalize(light.position - position);
                // Lo += calculateLightContribution(L, light.diffuse, attenuation, albedo, normal, roughness, metallic, view);
            }
        }

        // IBL Ambient Light
        {
            TextureCube irradiance_texture = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];
            TextureCube prefiltered_env_texture = ResourceDescriptorHeap[cbv_scene_const.prefiltered_env_texture_index];
            Texture2D brdf_lut_texture = ResourceDescriptorHeap[cbv_scene_const.brdf_integration_texture_index];

            float3 F0 = float3(0.04, 0.04, 0.04);
            F0 = lerp(F0, albedo, metallic);

            float NdotV = saturate(dot(normal, view));
            float3 reflection = reflect(-view, normal);

            float3 irradiance = irradiance_texture.Sample(sam_bilinear_clamp, normalize(reflection)).rgb;
            float mipLevel = roughness * cbv_scene_const.prefiltered_env_texture_max_lods;
            float3 prefilteredEnvColor = prefiltered_env_texture.SampleLevel(sam_bilinear_clamp,reflection, mipLevel).rgb;
            float2 brdfLUT = brdf_lut_texture.Sample(sam_bilinear_clamp, float2(NdotV, roughness)).rg;

            float3 F = fresnelSchlickRoughness(NdotV, F0, roughness);
            float3 kS = F;
            float3 kD = 1.0 - kS;
            kD *= 1.0 - metallic;

            float3 diffuse = kD * irradiance * albedo;
            float3 specular = prefilteredEnvColor * (F * brdfLUT.x + brdfLUT.y);

            float3 ambient = (diffuse + specular) * cbv_scene_const.ambient_light_intensity;
            Lo += ambient;
        }

        float3 color = Lo;

        hdr_texture[dispatch_id.xy] = float4(max(hdr_texture[dispatch_id.xy].rgb, color), 1.0);
    }
    else
    {
        TextureCube environment_texture = ResourceDescriptorHeap[cbv_scene_const.env_texture_index];
        float3 env = environment_texture.SampleLevel(sam_bilinear_clamp, normal, 0).rgb;
        env = clamp(env, 0, 32767.0f);
        hdr_texture[dispatch_id.xy] = float4(max(hdr_texture[dispatch_id.xy].rgb, env), 1.0);
    }
}

// https://lisyarus.github.io/blog/graphics/2022/07/30/point-light-attenuation.html
float calculatePointLightAttenuation(float d, float radius, float max_intensity, float falloff)
{
	float s = d / radius;

	if (s >= 1.0)
		return 0.0;

	float s2 = s * s;
    float one_minus_s2 = 1 - s2;

	return max_intensity * (one_minus_s2 * one_minus_s2) / (1 + falloff * s);
}