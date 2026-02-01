#define DIRECT3D12
#define STAGE_FRAG

#include "water_resources.hlsli"
#include "pbr.hlsli"

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

float4 PS_MAIN(VSOutput Input) : SV_TARGET0
{
    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instance_index = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instance_index * sizeof(InstanceData));

    float4 clip_position = mul(g_proj_view_mat, float4(Input.PositionWS, 1.0f));
    float4 screen_position = CalculateScreenPosition(clip_position);
    float2 screen_uv = screen_position.xy / screen_position.w;

    // Surface lighting
    float3 N = normalize(Input.Normal);
    float3 tangent_normal = 0;
    if (hasValidTexture(m_normal_map_1_texture_index) && hasValidTexture(m_normal_map_2_texture_index))
    {
        float3x3 TBN = ComputeTBN(N, normalize(Input.Tangent));
        Texture2D normal_texture_1 = ResourceDescriptorHeap[m_normal_map_1_texture_index];
        Texture2D normal_texture_2 = ResourceDescriptorHeap[m_normal_map_2_texture_index];

        float2 water_1_uv = Input.PositionWS.xz * m_normal_map_1_params.x + (normalize(m_normal_map_1_params.yz) * g_time * m_normal_map_1_params.x);
        float2 water_2_uv = Input.PositionWS.xz * m_normal_map_2_params.x + (normalize(m_normal_map_2_params.yz) * g_time * m_normal_map_2_params.x);

        float3 tangent_normal_1 = ReconstructNormal(SampleTex2D(normal_texture_1, g_linear_repeat_sampler, water_1_uv), m_normal_map_1_params.w);
        float3 tangent_normal_2 = ReconstructNormal(SampleTex2D(normal_texture_2, g_linear_repeat_sampler, water_2_uv), m_normal_map_2_params.w);
        tangent_normal = NormalBlend(tangent_normal_1, tangent_normal_2);
        N = normalize(mul(tangent_normal, TBN));

        screen_uv = (screen_position.xy + tangent_normal.xy * m_refraction_strength) / screen_position.w;
    }

    // Calculate water depth
    float scene_depth = g_depth_buffer.Sample(g_linear_clamp_edge_sampler, screen_uv).r;
    float eye_depth = max(0.000001f, LinearEyeDepth(scene_depth));
    float water_depth = eye_depth - screen_position.w; // / 10.0f;

    if (water_depth < 0)
    {
        screen_uv = screen_position.xy / screen_position.w;
    }

    water_depth = max(0.0000001f, water_depth);

    float3 scene_color = g_scene_color.Sample(g_linear_clamp_edge_sampler, screen_uv).rgb;

    float3 water_fog_color = m_water_fog_color.rgb;
    float underwater_fog_factor = exp2(-m_water_density * water_depth);

    Texture2D caustics_texture = ResourceDescriptorHeap[m_caustics_texture_index];
    float caustics_split = 0.0005;

    float2 caustics1_uv = Input.PositionWS.xz * 0.17f + float2(0.7, 0.5) * g_time * 0.025f;
    float caustics1_r = SampleTex2D(caustics_texture, g_linear_repeat_sampler, caustics1_uv + float2(caustics_split, caustics_split)).r;
    float caustics1_g = SampleTex2D(caustics_texture, g_linear_repeat_sampler, caustics1_uv + float2(caustics_split, -caustics_split)).g;
    float caustics1_b = SampleTex2D(caustics_texture, g_linear_repeat_sampler, caustics1_uv + float2(-caustics_split, -caustics_split)).b;

    float2 caustics2_uv = Input.PositionWS.xz * 0.19f + float2(-0.6, -0.8) * g_time * 0.024f;
    float caustics2_r = SampleTex2D(caustics_texture, g_linear_repeat_sampler, caustics2_uv + float2(caustics_split, caustics_split)).r;
    float caustics2_g = SampleTex2D(caustics_texture, g_linear_repeat_sampler, caustics2_uv + float2(caustics_split, -caustics_split)).g;
    float caustics2_b = SampleTex2D(caustics_texture, g_linear_repeat_sampler, caustics2_uv + float2(-caustics_split, -caustics_split)).b;

    float3 caustics1 = float3(caustics1_r, caustics1_g, caustics1_b);
    float3 caustics2 = float3(caustics2_r, caustics2_g, caustics2_b);
    float3 caustics = min(caustics1, caustics2);

    float3 color = lerp(water_fog_color, scene_color + caustics, underwater_fog_factor);

    SurfaceInfo surfaceInfo;
    surfaceInfo.position = Input.PositionWS.xyz;
    surfaceInfo.normal = N;
    surfaceInfo.view = normalize(g_cam_pos.xyz - Input.PositionWS.xyz);
    surfaceInfo.albedo = color;
    surfaceInfo.perceptual_roughness = max(0.04f, m_surface_roughness);
    surfaceInfo.metallic = 0.0;
    surfaceInfo.reflectance = 0.5;

    float3 Lo = float3(0.0f, 0.0f, 0.0f);

    ByteAddressBuffer lightsBuffer = ResourceDescriptorHeap[g_lights_buffer_index];
    // for (uint i = 0; i < g_lights_count; ++i)
    for (uint i = 0; i < 1; ++i)
    {
        GpuLight light = lightsBuffer.Load<GpuLight>(i * sizeof(GpuLight));
        Lo += ShadeLight(light, surfaceInfo, 1.0f);
    }

    // Simple depth-based fog
    float view_distance = length(g_cam_pos.xyz - Input.PositionWS.xyz);
    float fog_factor = exp(-g_fog_density * view_distance);
    Lo = lerp(g_fog_color, Lo, saturate(fog_factor));

    RETURN(float4(Lo, 1.0f));
}