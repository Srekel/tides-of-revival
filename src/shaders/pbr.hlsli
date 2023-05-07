#ifndef __PBR_HLSLI__
#define __PBR_HLSLI__

#include "common.hlsli"

// Based on https://github.com/PacktPublishing/3D-Graphics-Rendering-Cookbook/blob/master/data/shaders/chapter06/PBR.sp

struct PBRInfo
{
    float NdotL;
    float NdotV;
    float NdotH;
    float LdotH;
    float VdotH;
    float perceptualRoughness;
    float3 reflectance0;
    float3 reflectance90;
    float alphaRoughness;
    float3 diffuseColor;
    float3 specularColor;
    float3 n;
    float3 v;
};


// Calculation of the lighting contribution from an optional Image Based Light source.
float3 getIBLContribution(PBRInfo pbrInputs, float3 n, float3 reflection)
{
    TextureCube ibl_radiance_texture = ResourceDescriptorHeap[cbv_scene_const.radiance_texture_index];
    TextureCube ibl_specular_texture = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];
    Texture2D env_brdf_texture = ResourceDescriptorHeap[cbv_scene_const.brdf_integration_texture_index];

    // TODO:(gmodarelli) Pass this value in
    float mipCount = 8.0;
    float lod = pbrInputs.perceptualRoughness * mipCount;

    float2 brdfSamplePoint = clamp(float2(pbrInputs.NdotV, 1.0 - pbrInputs.perceptualRoughness), float2(0.0, 0.0), float2(1.0, 1.0));
    float3 brdf = env_brdf_texture.SampleLevel(sam_bilinear_clamp, brdfSamplePoint, 0.0f).rgb;

    // HDR envmaps are already linear
    float3 diffuseLight = ibl_radiance_texture.SampleLevel(sam_aniso_clamp, n.xyz, 0.0).rgb;
    float3 specularLight = ibl_specular_texture.SampleLevel(sam_aniso_clamp, reflection.xyz, lod).rgb;

    float3 diffuse = diffuseLight * pbrInputs.diffuseColor;
    float3 specular = specularLight * (pbrInputs.specularColor * brdf.x + brdf.y);

    return diffuse + specular;
}

// Disney Implementation of diffuse from Physically-Based Shading at Disney by Brent Burley.
// http://blog.selfshadow.com/publications/s2012-shading-course/burley/s2012_pbs_disney_brdf_notes_v3.pdf
float3 diffuseBurley(PBRInfo pbrInputs)
{
    float f90 = 2.0 * pbrInputs.LdotH * pbrInputs.LdotH * pbrInputs.alphaRoughness - 0.5;

    return (pbrInputs.diffuseColor / PI) * (1.0 + f90 * pow((1.0 - pbrInputs.NdotL), 5.0)) * (1.0 + f90 * pow((1.0 - pbrInputs.NdotV), 5.0));
}

// The following equation models the Fresnel reflectance term of the spec equation (aka F())
// Implementation of fresnel from [4], Equation 15
float3 specularReflection(PBRInfo pbrInputs)
{
    return pbrInputs.reflectance0 + (pbrInputs.reflectance90 - pbrInputs.reflectance0) * pow(clamp(1.0 - pbrInputs.VdotH, 0.0, 1.0), 5.0);
}

// This calculates the specular geometric attenuation (aka G()),
// where rougher material will reflect less light back to the viewer.
// This implementation is based on [1] Equation 4, and we adopt their modifications to
// alphaRoughness as input as originally proposed in [2].
float geometricOcclusion(PBRInfo pbrInputs)
{
    float NdotL = pbrInputs.NdotL;
    float NdotV = pbrInputs.NdotV;
    float rSqr = pbrInputs.alphaRoughness * pbrInputs.alphaRoughness;

    float attenuationL = 2.0 * NdotL / (NdotL + sqrt(rSqr + (1.0 - rSqr) * (NdotL * NdotL)));
    float attenuationV = 2.0 * NdotV / (NdotV + sqrt(rSqr + (1.0 - rSqr) * (NdotV * NdotV)));
    return attenuationL * attenuationV;
}

// The following equation(s) model the distribution of microfacet normals across the area being drawn (aka D())
// Implementation from "Average Irregularity Representation of a Roughened Surface for Ray Reflection" by T. S. Trowbridge, and K. P. Reitz
// Follows the distribution function recommended in the SIGGRAPH 2013 course notes from EPIC Games [1], Equation 3.
float microfacetDistribution(PBRInfo pbrInputs)
{
    float roughnessSq = pbrInputs.alphaRoughness * pbrInputs.alphaRoughness;
    float f = (pbrInputs.NdotH * roughnessSq - pbrInputs.NdotH) * pbrInputs.NdotH + 1.0;
    return roughnessSq / (PI * f * f);
}

float3 calculatePBRInputsMetallicRoughness(float3 albedo, float3 normal, float3 cameraPos, float3 worldPos, float roughness, float metallic, out PBRInfo pbrInputs)
{
    const float c_MinRoughness = 0.04;
    float perceptualRoughness = roughness;
    perceptualRoughness = clamp(perceptualRoughness, c_MinRoughness, 1.0);
    metallic = saturate(metallic);

    float alphaRoughness = perceptualRoughness * perceptualRoughness;

    float3 baseColor = albedo;

    float3 f0 = float3(0.04, 0.04, 0.04);
    float3 diffuseColor = baseColor * (float3(1.0, 1.0, 1.0) - f0);
    diffuseColor *= 1.0 - metallic;
    float3 specularColor = lerp(f0, baseColor, metallic);

    float reflectance = max(max(specularColor.r, specularColor.g), specularColor.b);

    float reflectance90 = clamp(reflectance * 25.0, 0.0, 1.0);
    float3 specularEnvironmentR0 = specularColor.rgb;
    float3 specularEnvironmentR90 = float3(1.0, 1.0, 1.0) * reflectance90;

    float3 n = normalize(normal);
    float3 v = normalize(cameraPos - worldPos);
    float3 reflection = normalize(reflect(-v, n));

    pbrInputs.NdotV = clamp(abs(dot(n, v)), 0.001, 1.0);
    pbrInputs.perceptualRoughness = perceptualRoughness;
    pbrInputs.reflectance0 = specularEnvironmentR0;
    pbrInputs.reflectance90 = specularEnvironmentR90;
    pbrInputs.alphaRoughness = alphaRoughness;
    pbrInputs.diffuseColor = diffuseColor;
    pbrInputs.specularColor = specularColor;
    pbrInputs.n = n;
    pbrInputs.v = v;

    // Calculate lighting contribution from image based lighting source (IBL)
    float3 color = getIBLContribution(pbrInputs, n, reflection);
    return color;
}

float3 calculatePBRLightContribution(inout PBRInfo pbrInputs, float3 lightDirection, float3 lightColor)
{
    float3 n = pbrInputs.n;
    float3 v = pbrInputs.v;
    float3 l = normalize(lightDirection); // Vector from surface point to light
    float3 h = normalize(l + v);          // Half vector between both l and v

    float NdotV = pbrInputs.NdotV;
    float NdotL = clamp(dot(n, l), 0.001, 1.0);
    float NdotH = clamp(dot(n, h), 0.0, 1.0);
    float LdotH = clamp(dot(l, h), 0.0, 1.0);
    float VdotH = clamp(dot(v, h), 0.0, 1.0);

    pbrInputs.NdotL = NdotL;
    pbrInputs.NdotH = NdotH;
    pbrInputs.LdotH = LdotH;
    pbrInputs.VdotH = VdotH;

    // Calculate the shading terms for the microfacet specular shading model
    float3 F = specularReflection(pbrInputs);
    float G = geometricOcclusion(pbrInputs);
    float D = microfacetDistribution(pbrInputs);

    // Calculation of analytical lighting contribution
    float3 diffuseContrib = (1.0 - F) * diffuseBurley(pbrInputs);
    float3 specContrib = F * G * D / (4.0 * NdotL * NdotV);
    // Obtain final intensity as reflectance (BRDF) scaled by the energy of the light (cosine law)
    float3 color = NdotL * lightColor * (diffuseContrib + specContrib);

    return color;
}

#endif // __PBR_HLSLI__