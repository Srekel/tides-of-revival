#define PI 3.1415926

#define GAMMA 2.2

float radicalInverseVdc(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return (float)bits * 2.3283064365386963e-10; // / 0x100000000
}

float2 hammersley(uint idx, uint n) {
    return float2(idx / (float)n, radicalInverseVdc(idx));
}

float3 importanceSampleGgx(float2 xi, float roughness, float3 n) {
    const float alpha = roughness * roughness;
    const float phi = 2.0 * PI * xi.x;
    const float cos_theta = sqrt((1.0 - xi.y) / (1.0 + (alpha * alpha - 1.0) * xi.y));
    const float sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    float3 h;
    h.x = sin_theta * cos(phi);
    h.y = sin_theta * sin(phi);
    h.z = cos_theta;

    const float3 up_vector = abs(n.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(0.0, 0.0, 1.0);
    const float3 tangent_x = normalize(cross(up_vector, n));
    const float3 tangent_y = cross(n, tangent_x);

    // Tangent to world space.
    return normalize(tangent_x * h.x + tangent_y * h.y + n * h.z);
}

float geometrySchlickGgx(float cos_theta, float roughness) {
    const float k = (roughness * roughness) * 0.5;
    return cos_theta / (cos_theta * (1.0 - k) + k);
}

float geometrySmith(float n_dot_l, float n_dot_v, float roughness) {
    return geometrySchlickGgx(n_dot_v, roughness) * geometrySchlickGgx(n_dot_l, roughness);
}

#define root_signature \
    "DescriptorTable(UAV(u0))"

RWTexture2D<float4> uav_brdf_integration_texture : register(u0);

float2 integrate(float roughness, float n_dot_v) {
    float3 v;
    v.x = 0.0;
    v.y = n_dot_v; // cos
    v.z = sqrt(1.0 - n_dot_v * n_dot_v); // sin

    const float3 n = float3(0.0, 1.0, 0.0);

    float a = 0.0;
    float b = 0.0;
    const uint num_samples = 1024;

    for (uint sample_idx = 0; sample_idx < num_samples; ++sample_idx) {
        const float2 xi = hammersley(sample_idx, num_samples);
        const float3 h = importanceSampleGgx(xi, roughness, n);
        const float3 l = normalize(2.0 * dot(v, h) * h - v);

        const float n_dot_l = saturate(l.y);
        const float n_dot_h = saturate(h.y);
        const float v_dot_h = saturate(dot(v, h));

        if (n_dot_l > 0.0) {
            const float g = geometrySmith(n_dot_l, n_dot_v, roughness);
            const float g_vis = g * v_dot_h / (n_dot_h * n_dot_v);
            const float fc = pow(1.0 - v_dot_h, 5.0);
            a += (1.0 - fc) * g_vis;
            b += fc * g_vis;
        }
    }
    return float2(a, b) / num_samples;
}

[RootSignature(root_signature)]
[numthreads(8, 8, 1)]
void csGenerateBrdfIntegrationTexture(uint3 dispatch_id : SV_DispatchThreadID) {
    float width, height;
    uav_brdf_integration_texture.GetDimensions(width, height);

    const float roughness = (dispatch_id.y + 1) / height;
    const float n_dot_v = (dispatch_id.x + 1) / width;
    const float2 result = integrate(roughness, n_dot_v);

    uav_brdf_integration_texture[dispatch_id.xy] = float4(result, 0.0, 1.0);
}
