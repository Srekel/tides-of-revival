#ifndef PI
#define PI 3.141592653589f
#endif

#define GAMMA 2.2

float radicalInverseVdc(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

float2 hammersley(uint idx, uint n) {
    return float2(float(idx) / float(n), radicalInverseVdc(idx));
}

float3 importanceSampleGgx(float2 xi, float roughness, float3 normal) {
    const float a = roughness * roughness;
    const float phi = 2.0 * PI * xi.x;
    float cosTheta2 = (1.0 - xi.y) / ((xi.y * (a - 1)) * (a + 1) + 1.0);
    const float cosTheta = sqrt(cosTheta2);
    const float sinTheta = sqrt(1.0 - cosTheta2);

    float3 halfVector = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

    const float3 up = abs(normal.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(0.0, 0.0, 1.0);
    const float3 tangent = normalize(cross(up, normal));
    const float3 bitangent = cross(normal, tangent);

    float3x3 TBN = float3x3(tangent, bitangent, normal);
    return normalize(mul(halfVector, TBN));
}

float geometrySmithCorrelated(float NdotV, float NdotL, float a) {
  float a2 = a * a;
  float GGXV = NdotL * sqrt((NdotV - NdotV * a2) * NdotV + a2);
  float GGXL = NdotV * sqrt((NdotL - NdotL * a2) * NdotL + a2);
  return 0.5 / (GGXV + GGXL);
}

#define root_signature \
    "DescriptorTable(UAV(u0))"

RWTexture2D<float2> uav_brdf_integration_texture : register(u0);

float2 integrate(float NdotV, float roughness) {
    float3 viewDir;
    viewDir.x = 0.0;
    viewDir.y = NdotV; // cos
    viewDir.z = sqrt(1.0 - NdotV * NdotV); // sin

    const float3 n = float3(0.0, 1.0, 0.0);

    float outputScale = 0.0;
    float outputBias = 0.0;
    const uint num_samples = 1024;

    for (uint sample_idx = 0; sample_idx < num_samples; ++sample_idx) {
        const float2 xi = hammersley(sample_idx, num_samples);
        const float3 halfVector = importanceSampleGgx(xi, roughness, n);
        const float3 l = normalize(2.0 * dot(viewDir, halfVector) * halfVector - viewDir);

        const float NdotL = saturate(l.y);

        if (NdotL > 0.0) {
            const float NdotH = saturate(halfVector.y);
            const float HdotV = saturate(dot(halfVector, viewDir));

            float a = roughness * roughness;
            const float V = geometrySmithCorrelated(NdotV, NdotL, a);
            const float g_vis = (4.0 * V * HdotV * NdotL) / NdotH;
            const float fc = pow(1.0 - HdotV, 5.0);

            outputScale += (1.0 - fc) * g_vis;
            outputBias += fc * g_vis;
        }
    }
    outputScale /= float(num_samples);
    outputBias /= float(num_samples);
    return float2(outputScale, outputBias);
}

[RootSignature(root_signature)]
[numthreads(8, 8, 1)]
void csGenerateBrdfIntegrationTexture(uint3 dispatch_id : SV_DispatchThreadID) {
    float width, height;
    uav_brdf_integration_texture.GetDimensions(width, height);

    if (dispatch_id.x < width && dispatch_id.y < height) {
        const float NdotV = float(dispatch_id.x + 1) / (width);
        const float roughness = float(dispatch_id.y + 1) / (height);
        const float2 result = integrate(NdotV, roughness);

        uav_brdf_integration_texture[dispatch_id.xy] = result;
    }
}
