#ifndef __LIGHTING_HLSL__
#define __LIGHTING_HLSL__

#include "pbr.hlsli"

float3 getPointShade(float3 pointToLight, MaterialInfo materialInfo, float3 normal, float3 view)
{
    AngularInfo angularInfo = getAngularInfo(pointToLight, normal, view);

    if (angularInfo.NdotL > 0.0 || angularInfo.NdotV > 0.0)
    {
        // Calculate the shading terms for the microfacet specular shading model
        float3 F = specularReflection(materialInfo, angularInfo);
        float Vis = visibilityOcclusion(materialInfo, angularInfo);
        float D = microfacetDistribution(materialInfo, angularInfo);

        // Calculation of analytical lighting contribution
        float3 diffuseContrib = (1.0 - F) * diffuse(materialInfo);
        float3 specularContrib = F * Vis * D;

        // Obtain final intensity as reflectance (BRDF) scaled by the energy of the light (cosine law)
        return angularInfo.NdotL * (diffuseContrib + specularContrib);
    }

    return float3(0.0, 0.0, 0.0);
}

float3 applyDirectionalLight(DirectionalLight light, MaterialInfo materialInfo, float3 normal, float3 view)
{
    float3 pointToLight = light.direction;
    float3 shade = getPointShade(pointToLight, materialInfo, normal, view);
    return light.intensity * light.color * shade;
}

// https://github.com/KhronosGroup/glTF/blob/master/extensions/2.0/Khronos/KHR_lights_punctual/README.md#range-property
float getRangeAttenuation(float range, float distance)
{
    if (range < 0.0)
    {
        // negative range means unlimited
        return 1.0;
    }
    return max(lerp(1, 0, distance / range), 0);
    //return max(min(1.0 - pow(distance / range, 4.0), 1.0), 0.0) / pow(distance, 2.0);
}

float3 applyPointLight(PointLight light, MaterialInfo materialInfo, float3 normal, float3 position, float3 view)
{
    float3 pointToLight = light.position - position;
    float distance = length(pointToLight);
    float attenuation = getRangeAttenuation(light.range, distance);
    float3 shade = getPointShade(pointToLight, materialInfo, normal, view);
    return attenuation * light.intensity * light.color * shade;
}

// Calculation of the lighting contribution from an optional Image Based Light source.
// Precomputed Environment Maps are required uniform inputs and are computed as outlined in [1].
// See our README.md on Environment Maps [3] for additional discussion.
float3 getIBLContribution(
    MaterialInfo materialInfo,
    float3 n,
    float3 v,
    float mipCount,
    TextureCube diffuseCube,
    TextureCube specularCube,
    Texture2D brdfTexture,
    SamplerState samplerState
)
{
    float NdotV = clamp(dot(n, v), 0.0, 1.0);

    float lod = clamp(materialInfo.perceptualRoughness * float(mipCount), 0.0, float(mipCount));
    float3 reflection = normalize(reflect(-v, n));

    float2 brdfSamplePoint = clamp(float2(NdotV, materialInfo.perceptualRoughness), float2(0.0, 0.0), float2(1.0, 1.0));
    // retrieve a scale and bias to F0. See [1], Figure 3
    float2 brdf = brdfTexture.Sample(samplerState, brdfSamplePoint).rg;

    float3 diffuseLight = diffuseCube.Sample(samplerState, n).rgb;
    float3 specularLight = specularCube.SampleLevel(samplerState, reflection, lod).rgb;

    float3 diffuse = diffuseLight * materialInfo.diffuseColor;
    float3 specular = specularLight * (materialInfo.specularColor * brdf.x + brdf.y);

    return diffuse + specular;
}

#endif // __LIGHTING_HLSL__
