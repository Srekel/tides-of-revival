#define DIRECT3D12
#define STAGE_FRAG

#include "draw_sky_resources.hlsli"

float4 PS_MAIN(VSOutput Input) : SV_Target
{
    float3 uv = normalize(Input.UV);

    float t = smoothstep(0.02f, 0.0f, g_time_of_day_01);
    t += smoothstep(0.48f, 0.5f, g_time_of_day_01);

    float3 starfield = starfield_cubemap.Sample(g_linear_repeat_sampler, uv).rgb;
    float3 skybox = skybox_cubemap.Sample(g_linear_repeat_sampler, uv).rgb;
    return float4(skybox + (starfield * t), 1.0f);
}