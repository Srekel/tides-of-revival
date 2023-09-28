#ifndef __PBR_HLSL__
#define __PBR_HLSL__

#include "utils.hlsli"
#include "constants.hlsli"
#include "common.hlsli"

// PBR Sampling
//
// Samples the GGX distribution along a given normal direction based on a given
// roughness. Xi should be a 2D random sampled number in the range [0..1].
// Returns the sampled halfvector in the space of the given normal.
//
float3 importanceSampleGgx(float2 Xi, float roughness, float3 normal) {
	const float a = roughness * roughness;
	const float phi = 2.0 * PI * Xi.x;
	float cosTheta2 = (1.0 - Xi.y) / ((Xi.y * (a - 1)) * (a + 1) + 1.0);
	const float cosTheta = sqrt(cosTheta2);
	const float sinTheta = sqrt(1.0 - cosTheta2);

	float3 halfVector = float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);

	const float3 up = abs(normal.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(0.0, 0.0, 1.0);
	const float3 tangent = normalize(cross(up, normal));
	const float3 bitangent = cross(normal, tangent);

	float3x3 TBN = float3x3(tangent, bitangent, normal);
	return normalize(mul(halfVector, TBN));
}

// Lambert lighting
// see https://seblagarde.wordpress.com/2012/01/08/pi-or-not-to-pi-in-game-lighting-equation/
float3 diffuse(MaterialInfo materialInfo)
{
    return materialInfo.diffuseColor / PI;
}

// The following equation models the Fresnel reflectance term of the spec equation (aka F())
// Implementation of fresnel from [4], Equation 15
float3 specularReflection(MaterialInfo materialInfo, AngularInfo angularInfo)
{
    return materialInfo.reflectance0 + (materialInfo.reflectace90 - materialInfo.reflectance0) * pow(clamp(1.0 - angularInfo.VdotH, 0.0, 1.0), 5.0);
}

// Smith Joint GGX
// Note: Vis = G / (4 * NdotL * NdotV)
// see Eric Heitz. 2014. Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs. Journal of Computer Graphics Techniques, 3
// see Real-Time Rendering. Page 331 to 336.
// see https://google.github.io/filament/Filament.md.html#materialsystem/specularbrdf/geometricshadowing(specularg)
float visibilityOcclusion(float NdotL, float NdotV, float alphaRoughness)
{
    float alphaRoughnessSq = alphaRoughness * alphaRoughness;

    float GGXV = NdotL * sqrt(NdotV * NdotV * (1.0 - alphaRoughnessSq) + alphaRoughnessSq);
    float GGXL = NdotV * sqrt(NdotL * NdotL * (1.0 - alphaRoughnessSq) + alphaRoughnessSq);

    float GGX = GGXV + GGXL;
    if (GGX > 0.0)
    {
        return 0.5 / GGX;
    }
    return 0.0;
}

float visibilityOcclusion(MaterialInfo materialInfo, AngularInfo angularInfo)
{
	return visibilityOcclusion(angularInfo.NdotL, angularInfo.NdotV, materialInfo.alphaRoughness);
}

// The following equation(s) model the distribution of microfacet normals across the area being drawn (aka D())
// Implementation from "Average Irregularity Representation of a Roughened Surface for Ray Reflection" by T. S. Trowbridge, and K. P. Reitz
// Follows the distribution function recommended in the SIGGRAPH 2013 course notes from EPIC Games [1], Equation 3.
float microfacetDistribution(MaterialInfo materialInfo, AngularInfo angularInfo)
{
    float alphaRoughnessSq = materialInfo.alphaRoughness * materialInfo.alphaRoughness;
    float f = (angularInfo.NdotH * alphaRoughnessSq - angularInfo.NdotH) * angularInfo.NdotH + 1.0;
    return alphaRoughnessSq / (PI * f * f + 0.000001f);
}

#endif // __PBR_HLSL__