#ifndef __PBR_HLSL__
#define __PBR_HLSL__

#include "common.hlsli"

// Trowbridge-Reitz GGX normal distribution function.
float distributionGgx(float3 n, float3 h, float alpha) {
    float alpha_sq = alpha * alpha;
    float n_dot_h = saturate(dot(n, h));
    float k = n_dot_h * n_dot_h * (alpha_sq - 1.0) + 1.0;
    return alpha_sq / (PI * k * k);
}

float geometrySchlickGgx(float x, float k) {
    return x / (x * (1.0 - k) + k);
}

float geometrySmith(float3 n, float3 v, float3 l, float k) {
    float n_dot_v = saturate(dot(n, v));
    float n_dot_l = saturate(dot(n, l));
    return geometrySchlickGgx(n_dot_v, k) * geometrySchlickGgx(n_dot_l, k);
}

float3 fresnelSchlick(float h_dot_v, float3 f0) {
    return f0 + (float3(1.0, 1.0, 1.0) - f0) * pow(1.0 - h_dot_v, 5.0);
}

// TODO: pass needed frame data in
float3 pointLight(float3 light_position, float4 light_data, float3 position, float3 base_color, float3 v, float3 f0, float3 n, float alpha, float k, float metallic, float time) {
    float3 lvec = light_position - position;

    float3 l = normalize(lvec);
    float3 h = normalize(l + v);

    float range = light_data.w;
    float range_sq = range * range;
    float distance_sq = dot(lvec, lvec);
    if (range_sq < distance_sq) {
        return float3(0.0, 0.0, 0.0);
    }

    // https://lisyarus.github.io/blog/graphics/2022/07/30/point-light-attenuation.html
    float distance = length(lvec);
    float attenuation_real = min(1.0, 1.0 / (1.0 + distance_sq));
    float attenuation_el = (distance_sq / range_sq ) * (2.0 * distance / range - 3.0) + 1.0;
    float attenuation_nik_s2 = distance_sq / range_sq;
    float attenuation_nik = (1.0 - attenuation_nik_s2) * (1.0 - attenuation_nik_s2) / (1.0 + 5.0 * attenuation_nik_s2);
    float attenuation = attenuation_nik;
    float variance = 1.0 + 0.2 * sin(time * 1.7);
    float3 radiance = light_data.xyz * attenuation * variance;

    float3 f = fresnelSchlick(saturate(dot(h, v)), f0);

    float ndf = distributionGgx(n, h, alpha);
    float g = geometrySmith(n, v, l, k);

    float3 numerator = ndf * g * f;
    float denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
    float3 specular = numerator / max(denominator, 0.001);

    float3 ks = f;
    float3 kd = (float3(1.0, 1.0, 1.0) - ks) * (1.0 - metallic);

    float n_dot_l = saturate(dot(n, l));
    // return base_color * radiance * n_dot_l;
    return (kd * base_color / PI + specular) * radiance * n_dot_l;
}

struct PBRInput {
    float3 view_position;
    float3 position;
    float3 normal;
    float roughness;
    // TMP
    float time;
};

float3 pbrShading(float3 base_color, PBRInput input, float4 light_positions[MAX_LIGHTS], float4 light_radiances[MAX_LIGHTS], uint light_count) {
    float3 v = normalize(input.view_position - input.position);
    float3 n = normalize(input.normal);

    float ao = 1.0;
    float roughness = input.roughness;
    float metallic = 0.0;
    if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
    roughness = abs(roughness);

    float alpha = roughness * roughness;
    float k = alpha + 1.0;
    k = (k * k) / 8.0;
    float3 f0 = float3(0.04, 0.04, 0.04);
    f0 = lerp(f0, base_color, metallic);

    float3 lo = float3(0.0, 0.0, 0.0);
    for (uint light_index = 0u; light_index < light_count; light_index = light_index + 1u) {
        float3 lightContrib = pointLight(light_positions[light_index].xyz, light_radiances[light_index], input.position, base_color, v, f0, n, alpha, k, metallic, input.time);
        lo += lightContrib;
    }

    // TMP
    float sun_height = sin(input.time * 0.5);
    float3 sun_color = float3(1.0, 0.914 * sun_height, 0.843 * sun_height * sun_height);
    float3 sun = max(0.0, sun_height) * 0.3 * base_color * (0.0 + saturate(dot(n, normalize(sun_color))));
    float3 sun2 = 0.5 * base_color * saturate(dot(n, normalize( float3(0.0, 1.0, 0.0))));

    float ambient_day_value = 0.0002 * saturate(sun_height + 0.1);
    float3 ambient_day = float3(ambient_day_value, ambient_day_value, ambient_day_value) * float3(0.9, 0.9, 1.0) * base_color;
    float ambient_night_value = 0.05 * saturate(sign(-sun_height + 0.1));
    float3 ambient_night = float3(ambient_night_value, ambient_night_value, ambient_night_value) * float3(0.2, 0.2, 1.0) * base_color;
    float3 ambient = (ambient_day + ambient_night) * ao * saturate(dot(n, float3(0.0, 1.0, 0.0)));
    float fog_dist = length(input.position - input.view_position);
    float fog_start = 500.0;
    float fog_end = 2500.0;
    float fog = saturate((fog_dist - fog_start) / (fog_end - fog_start));
    float3 color = ambient + lo + sun;
    color = lerp(color, float3(0.5, 0.5, 0.4), 1.0 * saturate(fog * fog * max(0.0, sun_height)));
    return color;
}

#endif