#define DIRECT3D12
#define STAGE_FRAG

#include "water_resources.hlsl"
#include "pbr.hlsl"
#include "utils.hlsl"

float4 CalculateScreenPosition(float4 clip_position)
{
    float4 screen_position = clip_position * 0.5f;
    screen_position.xy = float2(screen_position.x, screen_position.y * -1.0) + screen_position.w;
    screen_position.zw = clip_position.zw;

    return screen_position;
}

float LinearEyeDepth(float depth)
{
    return 1.0 / (g_depth_buffer_params.z * depth + g_depth_buffer_params.w);
}

float4 PS_MAIN(VSOutput Input) : SV_TARGET0 {
    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instance_index = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instance_index * sizeof(InstanceData));

    ByteAddressBuffer material_buffer = ResourceDescriptorHeap[g_instanceRootConstants.materialBufferIndex];
    WaterMaterial material = material_buffer.Load<WaterMaterial>(instance.materialBufferOffset);

    float4 clip_position = mul(g_proj_view_mat, float4(Input.PositionWS, 1.0f));
    float4 screen_position = CalculateScreenPosition(clip_position);
    float2 screen_uv = screen_position.xy / screen_position.w;

    // Calculate water depth
    float scene_depth = g_depth_buffer.Sample(g_linear_clamp_edge_sampler, screen_uv).r;
    float eye_depth = max(0.000001f, LinearEyeDepth(scene_depth));
    float water_depth = max(0.000001f, eye_depth - screen_position.w);

    float3 scene_color = g_scene_color.Sample(g_linear_clamp_edge_sampler, screen_uv).rgb;

    float3 absorption_color = material.m_absorption_color.rgb;
    float absorption_coefficient = material.m_absorption_coefficient;

    absorption_coefficient = 1.0f - exp2(-absorption_coefficient * water_depth);
    absorption_color *= absorption_coefficient;
    absorption_color = saturate(absorption_color);

    float3 underwater_color = saturate(scene_color - absorption_color);

    // Surface lighting
    float3 N = normalize(Input.Normal);
    if (hasValidTexture(material.m_normal_map_1_texture_index) && hasValidTexture(material.m_normal_map_2_texture_index)) {
        float3x3 TBN = ComputeTBN(N, normalize(Input.Tangent));
        Texture2D normal_texture_1 = ResourceDescriptorHeap[NonUniformResourceIndex(material.m_normal_map_1_texture_index)];
        Texture2D normal_texture_2 = ResourceDescriptorHeap[NonUniformResourceIndex(material.m_normal_map_2_texture_index)];

        float2 water_1_uv = Input.PositionWS.xz * material.m_normal_map_1_params.x + (normalize(material.m_normal_map_1_params.yz) * g_time * material.m_normal_map_1_params.x);
        float2 water_2_uv = Input.PositionWS.xz * material.m_normal_map_2_params.x + (normalize(material.m_normal_map_2_params.yz) * g_time * material.m_normal_map_2_params.x);

        float3 tangent_normal_1 = ReconstructNormal(SampleTex2D(normal_texture_1, g_linear_repeat_sampler, water_1_uv), material.m_normal_map_1_params.w);
        float3 tangent_normal_2 = ReconstructNormal(SampleTex2D(normal_texture_2, g_linear_repeat_sampler, water_2_uv), material.m_normal_map_2_params.w);
        float3 tangent_normal = NormalBlend(tangent_normal_1, tangent_normal_2);
        N = normalize(mul(tangent_normal, TBN));
    }
    float3 V = normalize(g_cam_pos.xyz - Input.PositionWS);
    float3 L = normalize(-g_sun_direction.xyz);
    float3 radiance = g_sun_color_intensity.rgb * g_sun_color_intensity.a;
    float n_dot_l = max(dot(N, L), 0.0f);
    float3 lit_surface = FilamentBRDF(N, V, L, float3(0, 0, 0), material.m_surface_roughness, 0, 1.0f) * radiance * n_dot_l;
    lit_surface += EnvironmentBRDF(N, V, float3(0, 0, 0), material.m_surface_roughness, 0) * 0.3f;

    // Blending underwater and surface color
    float3 color = lerp(underwater_color, lit_surface + underwater_color, material.m_surface_opacity);
    color = lit_surface;
    // Transparent edges
    color = lerp(scene_color, color, saturate(water_depth));

    return float4(color, 1);
}