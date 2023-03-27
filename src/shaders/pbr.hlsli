#ifndef __PBR_HLSL__
#define __PBR_HLSL__

#include "common.hlsli"

float geometrySchlickGgx(float cos_theta, float roughness) {
    const float k = (roughness * roughness) * 0.5;
    return cos_theta / (cos_theta * (1.0 - k) + k);
}

float geometrySmith(float n_dot_l, float n_dot_v, float roughness) {
    return geometrySchlickGgx(n_dot_v, roughness) * geometrySchlickGgx(n_dot_l, roughness);
}

float3 fresnelSchlickRoughness(float cos_theta, float3 f0, float roughness) {
    return f0 + (max(1.0 - roughness, f0) - f0) * pow(1.0 - cos_theta, 5.0);
}

// TODO: pass needed frame data in
// float3 pointLight(float3 light_position, float4 light_data, float3 position, float3 base_color, float3 v, float3 f0, float3 n, float alpha, float k, float metallic, float time) {
//     float3 lvec = light_position - position;
// 
//     float3 l = normalize(lvec);
//     float3 h = normalize(l + v);
// 
//     float range = light_data.w;
//     float range_sq = range * range;
//     float distance_sq = dot(lvec, lvec);
//     if (range_sq < distance_sq) {
//         return float3(0.0, 0.0, 0.0);
//     }
// 
//     // https://lisyarus.github.io/blog/graphics/2022/07/30/point-light-attenuation.html
//     float distance = length(lvec);
//     float attenuation_real = min(1.0, 1.0 / (1.0 + distance_sq));
//     float attenuation_el = (distance_sq / range_sq ) * (2.0 * distance / range - 3.0) + 1.0;
//     float attenuation_nik_s2 = distance_sq / range_sq;
//     float attenuation_nik = (1.0 - attenuation_nik_s2) * (1.0 - attenuation_nik_s2) / (1.0 + 5.0 * attenuation_nik_s2);
//     float attenuation = attenuation_nik;
//     float variance = 1.0 + 0.2 * sin(time * 1.7);
//     float3 radiance = light_data.xyz * attenuation * variance;
// 
//     float3 f = fresnelSchlick(saturate(dot(h, v)), f0);
// 
//     float ndf = distributionGgx(n, h, alpha);
//     float g = geometrySmith(n, v, l, k);
// 
//     float3 numerator = ndf * g * f;
//     float denominator = 4.0 * saturate(dot(n, v)) * saturate(dot(n, l));
//     float3 specular = numerator / max(denominator, 0.001);
// 
//     float3 ks = f;
//     float3 kd = (float3(1.0, 1.0, 1.0) - ks) * (1.0 - metallic);
// 
//     float n_dot_l = saturate(dot(n, l));
//     // return base_color * radiance * n_dot_l;
//     return (kd * base_color / PI + specular) * radiance * n_dot_l;
// }

struct PBRInput {
    float3 base_color;
    float3 view_direction;
    float3 position;
    float3 normal;
    float roughness;
    float metallic;
    float ao;
    float3 ibl_irradiance;
    float3 ibl_specular;
    float2 ibl_brdf;
    // TMP
    float time;
};

float3 pbrShading(PBRInput input, float4 light_positions[MAX_LIGHTS], float4 light_radiances[MAX_LIGHTS], uint light_count) {
    const float n_dot_v = saturate(dot(input.view_direction, input.normal));
    float3 f0 = float3(0.04, 0.04, 0.04);
    f0 = lerp(f0, input.base_color, input.metallic);

    const float3 r = reflect(-input.view_direction, input.normal);
    const float3 f = fresnelSchlickRoughness(n_dot_v, f0, input.roughness);

    const float3 kd = (1.0 - f) * (1.0 - input.metallic);

    const float3 diffuse = input.ibl_irradiance * input.base_color;
    const float3 specular = input.ibl_specular * (f * input.ibl_brdf.x + input.ibl_brdf.y);
    const float3 ambient = (kd * diffuse + specular) * input.ao;

    // TODO(gmodarelli): Add directional light contribution
    // TODO(gmodarelli): Add point lights contribution
    return ambient;

    // float3 v = normalize(input.view_position - input.position);
    // float3 n = normalize(input.normal);

    // float ao = 1.0;
    // float roughness = input.roughness;
    // float metallic = 0.0;
    // if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
    // roughness = abs(roughness);

    // float alpha = roughness * roughness;
    // float k = alpha + 1.0;
    // k = (k * k) / 8.0;
    // float3 f0 = float3(0.04, 0.04, 0.04);
    // f0 = lerp(f0, base_color, metallic);

    // float3 lo = float3(0.0, 0.0, 0.0);
    // for (uint light_index = 0u; light_index < light_count; light_index = light_index + 1u) {
    //     float3 lightContrib = pointLight(light_positions[light_index].xyz, light_radiances[light_index], input.position, base_color, v, f0, n, alpha, k, metallic, input.time);
    //     lo += lightContrib;
    // }

    // float sun_height = sin(input.time * 0.5);
    // float3 sun_color = float3(1.0, 0.914 * sun_height, 0.843 * sun_height * sun_height);
    // float3 sun = max(0.0, sun_height) * 0.3 * base_color * (0.0 + saturate(dot(n, normalize(sun_color))));
    // float3 sun2 = 0.5 * base_color * saturate(dot(n, normalize( float3(0.0, 1.0, 0.0))));

    // float ambient_day_value = 0.0002 * saturate(sun_height + 0.1);
    // float3 ambient_day = float3(ambient_day_value, ambient_day_value, ambient_day_value) * float3(0.9, 0.9, 1.0) * base_color;
    // float ambient_night_value = 0.05 * saturate(sign(-sun_height + 0.1));
    // float3 ambient_night = float3(ambient_night_value, ambient_night_value, ambient_night_value) * float3(0.2, 0.2, 1.0) * base_color;
    // float3 ambient = (ambient_day + ambient_night) * ao * saturate(dot(n, float3(0.0, 1.0, 0.0)));
    // float fog_dist = length(input.position - input.view_position);
    // float fog_start = 500.0;
    // float fog_end = 2500.0;
    // float fog = saturate((fog_dist - fog_start) / (fog_end - fog_start));
    // float3 color = ambient + lo + sun;
    // color = lerp(color, float3(0.5, 0.5, 0.4), 1.0 * saturate(fog * fog * max(0.0, sun_height)));
    // return color;
}

#endif