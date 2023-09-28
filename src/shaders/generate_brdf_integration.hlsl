#include "random.hlsli"
#include "constants.hlsli"
#include "pbr.hlsli"

#define root_signature \
    "DescriptorTable(UAV(u0))"

RWTexture2D<float2> uav_brdf_integration_texture : register(u0);

float2 integrateBrdf(float NdotV, float roughness) {
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
            const float V = visibilityOcclusion(NdotV, NdotL, a);
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
        const float2 result = integrateBrdf(NdotV, roughness);

        uav_brdf_integration_texture[dispatch_id.xy] = result;
    }
}
