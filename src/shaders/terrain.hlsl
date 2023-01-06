#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_ALL), " /* index 0 */ \
    "CBV(b1, visibility = SHADER_VISIBILITY_ALL)"   /* index 1 */

struct DrawConst {
    float4x4 object_to_world;
    float4 basecolor_roughness;
};

struct FrameConst {
    float4x4 world_to_clip;
    float3 camera_position;
    float time;
    uint padding1;
    uint padding2;
    uint padding3;
    uint light_count;
    float4 light_positions[32];
    float4 light_radiances[32];
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);

struct VertexOut {
    float4 position_vs : SV_Position;
    float3 position : TEXCOORD0;
    float3 normal : NORMAL;
};

// TODO: Move these into a PBR.hlsli include file
#define PI 3.1415926

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
float3 pointLight(uint light_index, float3 position, float3 base_color, float3 v, float3 f0, float3 n, float alpha, float k, float metallic) {
        float3 lvec = cbv_frame_const.light_positions[light_index].xyz - position;
       //  lvec.y += sin(cbv_frame_const.time * 1.0) * 5.0;

        float3 l = normalize(lvec);
        float3 h = normalize(l + v);

        float4 lightData = cbv_frame_const.light_radiances[light_index];
        float range = lightData.w;
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
        float variance = 1.0 + 0.2 * sin(cbv_frame_const.time * 1.7);
        float3 radiance = lightData.xyz * attenuation * variance;

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

[RootSignature(ROOT_SIGNATURE)]
VertexOut vsMain(float3 position : POSITION, float3 normal : _Normal) {
    VertexOut output = (VertexOut)0;

    const float4x4 object_to_clip = mul(cbv_draw_const.object_to_world, cbv_frame_const.world_to_clip);
    output.position_vs = mul(float4(position, 1.0), object_to_clip);
    output.position = mul(float4(position, 1.0), cbv_draw_const.object_to_world).xyz;
    output.normal = normal; // object-space normal

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psMain(VertexOut input, out float4 out_color : SV_Target0) {
    float3 v = normalize(cbv_frame_const.camera_position - input.position);
    float3 n = normalize(input.normal);

    float3 colors[5] = {
        float3(0.0, 0.1, 0.7),
        float3(1.0, 1.0, 0.0),
        float3(0.3, 0.8, 0.2),
        float3(0.7, 0.7, 0.7),
        float3(0.95, 0.95, 0.95),
    };

    float3 base_color = colors[0];
    base_color = lerp(base_color, colors[1], step(0.005, input.position.y * 0.01));
    base_color = lerp(base_color, colors[2], step(0.02, input.position.y * 0.01));
    base_color = lerp(base_color, colors[3], step(1.0, input.position.y * 0.01 + 0.5 * (1.0 - dot(n, float3(0.0, 1.0, 0.0))) ));
    base_color = lerp(base_color, colors[4], step(3.5, input.position.y * 0.01 + 1.5 * dot(n, float3(0.0, 1.0, 0.0)) ));

    float ao = 1.0;
    float roughness = cbv_draw_const.basecolor_roughness.a;
    float metallic = 0.0;
    if (roughness < 0.0) { metallic = 1.0; } else { metallic = 0.0; }
    roughness = abs(roughness);

    float alpha = roughness * roughness;
    float k = alpha + 1.0;
    k = (k * k) / 8.0;
    float3 f0 = float3(0.04, 0.04, 0.04);
    f0 = lerp(f0, base_color, metallic);

    float3 lo = float3(0.0, 0.0, 0.0);
    for (uint light_index = 0u; light_index < cbv_frame_const.light_count; light_index = light_index + 1u) {
        float3 lightContrib = pointLight(light_index, input.position, base_color, v, f0, n, alpha, k, metallic);
        lo += lightContrib;
    }

    float sun_height = sin(cbv_frame_const.time * 0.5);
    float3 sun_color = float3(1.0, 0.914 * sun_height, 0.843 * sun_height * sun_height);
    float3 sun = max(0.0, sun_height) * 0.3 * base_color * (0.0 + saturate(dot(n, normalize(sun_color))));
    float3 sun2 = 0.5 * base_color * saturate(dot(n, normalize( float3(0.0, 1.0, 0.0))));

    float ambient_day_value = 0.0002 * saturate(sun_height + 0.1);
    float3 ambient_day = float3(ambient_day_value, ambient_day_value, ambient_day_value) * float3(0.9, 0.9, 1.0) * base_color;
    float ambient_night_value = 0.05 * saturate(sign(-sun_height + 0.1));
    float3 ambient_night = float3(ambient_night_value, ambient_night_value, ambient_night_value) * float3(0.2, 0.2, 1.0) * base_color;
    float3 ambient = (ambient_day + ambient_night) * ao * saturate(dot(n, float3(0.0, 1.0, 0.0)));
    float fog_dist = length(input.position - cbv_frame_const.camera_position);
    float fog_start = 500.0;
    float fog_end = 2500.0;
    float fog = saturate((fog_dist - fog_start) / (fog_end - fog_start));
    float3 color = ambient + lo + sun;
    color = lerp(color, float3(0.5, 0.5, 0.4), 1.0 * saturate(fog * fog * max(0.0, sun_height)));
    float gamma = 1.0 / 2.2;
    color = pow(color, float3(gamma, gamma, gamma));

    out_color.rgb = color;
    out_color.a = 1;
}