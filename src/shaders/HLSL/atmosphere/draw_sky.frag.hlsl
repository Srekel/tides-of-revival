#define DIRECT3D12
#define STAGE_FRAG

#define PI 3.14159265359
#include "draw_sky_resources.hlsli"

float RayTraceSphere(float3 origin, float3 direction, float3 position, float radius, out float3 normal)
{
    float3 rc = origin - position;
    float c = dot(rc, rc) - (radius * radius);
    float b = dot(direction, rc);
    float d = b * b - c;
    float t = -b - sqrt(abs(d));
    float st = step(0.0f, min(t, d));

    normal = normalize(-position + (origin + direction * t));

    if (st > 0.0f)
    {
        return 1.0f;
    }

    return 0.0f;
}

float3 RotateAroundY(float3 direction, float radians)
{
    float sina, cosa;
    sincos(radians, sina, cosa);
    float2x2 m = float2x2(cosa, -sina, sina, cosa);
    return float3(mul(m, direction.xz), direction.y).xzy;
}

float4 PS_MAIN(VSOutput Input) : SV_Target
{
    float3 uv = normalize(Input.UV);
    float3 startfield_uv = RotateAroundY(uv, g_time_of_day_01 * PI * 2.0f);

    // Starfield
    float starfield_opacity = smoothstep(0.02f, 0.0f, g_time_of_day_01);
    starfield_opacity += smoothstep(0.48f, 0.5f, g_time_of_day_01);
    float3 starfield = starfield_cubemap.Sample(g_linear_repeat_sampler, startfield_uv).rgb;
    starfield *= starfield_opacity;

    // Skybox
    float3 skybox = skybox_cubemap.Sample(g_linear_repeat_sampler, uv).rgb;

    // Moon
    float moon_opacity = smoothstep(0.1f, 0.0f, g_time_of_day_01);
    moon_opacity += smoothstep(0.4f, 0.5f, g_time_of_day_01);
    moon_opacity = max(0.2, moon_opacity);
    float3 moon_normal = 0;
    float3 moon = RayTraceSphere(0, uv, normalize(float3(-1, .5, 0)), 0.035, moon_normal).rrr;
    moon = lerp(skybox, moon, moon_opacity);

    // Composite
    return float4(skybox + starfield + moon, 1.0f);
}