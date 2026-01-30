#define DIRECT3D12
#define STAGE_FRAG

#define PI 3.14159265359
#include "draw_sky_resources.hlsli"
#include "../utils.hlsli"

float RayTraceSphere(float3 origin, float3 direction, float3 position, float radius, out float3 normal) {
    float3 rc = origin - position;
    float c = dot(rc, rc) - (radius * radius);
    float b = dot(direction, rc);
    float d = b * b - c;
    float t = -b - sqrt(abs(d));
    float st = step(0.0f, min(t, d));

    normal = normalize(-position + (origin + direction * t));

    if (st > 0.0f) {
        return 1.0f;
    }

    return 0.0f;
}

float3 RotateAroundY(float3 direction, float radians) {
    float sina, cosa;
    sincos(radians, sina, cosa);
    float2x2 m = float2x2(cosa, -sina, sina, cosa);
    return float3(mul(m, direction.xz), direction.y).xzy;
}

float3 RotateAboutAxis(float3 direction, float3 axis, float rotation) {
    float s = sin(rotation);
    float c = cos(rotation);
    float one_minus_c = 1.0 - c;

    axis = normalize(axis);
    float3x3 rot_mat = {
        one_minus_c * axis.x * axis.x + c, one_minus_c * axis.x * axis.y - axis.z * s, one_minus_c * axis.z * axis.x + axis.y * s,
        one_minus_c * axis.x * axis.y + axis.z * s, one_minus_c * axis.y * axis.y + c, one_minus_c * axis.y * axis.z - axis.x * s,
        one_minus_c * axis.z * axis.x - axis.y * s, one_minus_c * axis.y * axis.z + axis.x * s, one_minus_c * axis.z * axis.z + c
    };

    return mul(rot_mat, direction);
}

float2 SampleSphericalMap(float3 v) {
    const float2 invAtan = float2(0.1591, 0.3183);
    float2 uv = float2(atan2(v.z, v.x), asin(v.y));
    uv *= invAtan;
    uv += 0.5;
    return uv;
}

float4 PS_MAIN(VSOutput Input) : SV_Target {
    float3 uv = normalize(Input.UV);
    float3 starfield_uv = RotateAboutAxis(uv, float3(1, 0, 0), 30.0f * PI / 180.0f);
    starfield_uv = RotateAboutAxis(starfield_uv, float3(0, 1, 0), g_time_of_day_01 * PI * 2.0f);

    // Starfield
    float starfield_opacity = smoothstep(0.02f, 0.0f, g_time_of_day_01);
    starfield_opacity += smoothstep(0.48f, 0.5f, g_time_of_day_01);
    float3 starfield = starfield_cubemap.Sample(g_linear_repeat_sampler, starfield_uv).rgb;
    starfield *= starfield_opacity;

    // Skybox
    float3 skybox = skybox_cubemap.Sample(g_linear_repeat_sampler, uv).rgb;

    float3 sun = 0;
    float3 sun_normal = 0;
    if (RayTraceSphere(float3(0, 0, 0), uv, normalize(sun_direction), 0.075, sun_normal).r > 0) {
        sun = sRGBToLinear_Float3(sun_color) * sun_intensity;
        starfield = 0;
    }

    // Moon
    Texture2D moon_texture = ResourceDescriptorHeap[g_moon_texture_index];

    float3 moon = 0;
    float3 moon_normal = 0;
    if (RayTraceSphere(float3(0, 0, 0), uv, normalize(moon_direction), 0.1, moon_normal).r > 0) {
        moon_normal = RotateAroundY(moon_normal, frac(g_time * 0.00025) * PI * 2.0f);
        float2 moon_uv = SampleSphericalMap(moon_normal);
        // float4 moon_sample = moon_texture.Sample(g_linear_clamp_edge_sampler, (Input.MoonPosition.xy * 4) + float2(0.5, 0.5));
        float4 moon_sample = moon_texture.Sample(g_linear_clamp_edge_sampler, moon_uv);
        moon = moon_sample.rgb * 2.0 * moon_intensity;
        starfield = 0;
    }

    // Composite
    return float4(skybox + sun + moon + starfield, 1.0f);
}