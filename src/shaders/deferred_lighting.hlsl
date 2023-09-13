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

    if (gbuffer_0_sample.a > 0)
    {
        float3 position = getPositionFromDepth(depth, uv, cbv_frame_const.view_projection_inverted);
        float3 N = gbuffer_1_sample.xyz;
        float3 V = normalize(cbv_frame_const.camera_position - position);

        MaterialProperties material_properties;
        material_properties.baseColor = gbuffer_0_sample.rgb;
        material_properties.metalness = gbuffer_2_sample.g;
        material_properties.emissive = gbuffer_2_sample.b * gbuffer_0_sample.rgb;
        material_properties.roughness = gbuffer_2_sample.r;
        material_properties.transmissivness = 0;
        material_properties.reflectance = 0.5;
        material_properties.opacity = gbuffer_0_sample.a;


        ByteAddressBuffer point_lights_buffer = ResourceDescriptorHeap[cbv_scene_const.point_lights_buffer_index];

        float3 Lo = float3(0.0, 0.0, 0.0);

        // Main Directional Light
        {
            float3 L = cbv_scene_const.main_light_direction;
            float attenuation = 1.0;

            // add to outgoing radiance Lo
            Lo += calculateLightContribution(N, L, V, material_properties, cbv_scene_const.main_light_radiance, attenuation);
        }

        // Point Lights
        for (uint i = 0; i < cbv_scene_const.point_lights_count; i++)
        {
            PointLight light = point_lights_buffer.Load<PointLight>(i * sizeof(PointLight));
            float3 L = normalize(light.position - position);
            float attenuation = calculatePointLightAttenuation(distance(light.position, position), light.radius, light.max_intensity, light.falloff);

            // add to outgoing radiance Lo
            Lo += calculateLightContribution(N, L, V, material_properties, light.radiance, attenuation);
        }


        float ambient_factor = 0.03;
        float3 ambient = float3(ambient_factor, ambient_factor, ambient_factor) * material_properties.baseColor;
        float3 color = ambient + Lo;

        hdr_texture[dispatch_id.xy] = float4(color, 1.0);
    }
    else
    {
        TextureCube environment_texture = ResourceDescriptorHeap[cbv_scene_const.radiance_texture_index];
        float3 N = gbuffer_1_sample.xyz;
        float3 env = environment_texture.SampleLevel(sam_bilinear_clamp, N, 0).rgb;
        hdr_texture[dispatch_id.xy] = float4(clamp(env, 0, 32767.0f), 1.0);
    }
}

// https://lisyarus.github.io/blog/graphics/2022/07/30/point-light-attenuation.html
float calculatePointLightAttenuation(float distance, float radius, float max_intensity, float falloff)
{
	float s = distance / radius;

	if (s >= 1.0)
		return 0.0;

	float s2 = s * s;
    float one_minus_s2 = 1 - s2;

	return max_intensity * (one_minus_s2 * one_minus_s2) / (1 + falloff * s);
}