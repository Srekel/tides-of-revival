#ifndef __PBR_HLSL__
#define __PBR_HLSL__

#include "utils.hlsli"
#include "constants.hlsli"

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

// Microfacet model
//
// Returns the GGX microfacet distribution function.
//
float distributionGGX(float NdotH, float a) {
	float a2 = a * a;
	float f = (NdotH * a2 - NdotH) * NdotH + 1.0;
	return a2 / (PI * f * f);
}

//
// Returns the geometric visibility term based on the Smith-GGX approximation.
// This is the shadowing-masking term used in Cook-Torrance microfacet models.
// This formulation cancels out the standard BRDF denominator (4 * NdotV *
// NdotL).
// https://google.github.io/filament/Filament.html#materialsystem/specularbrdf/geometricshadowing(specularg)
//
float visibilitySmithGGXCorrelated(float NdotV, float NdotL, float a) {
	float a2 = a * a;
	float GGXV = NdotL * sqrt((NdotV - NdotV * a2) * NdotV + a2);
	float GGXL = NdotV * sqrt((NdotL - NdotL * a2) * NdotL + a2);
	return 0.5 / (GGXV + GGXL);
}

//
// Returns Schlick's approximation of the Fresnel factor.
//   F(w_i, h) = F0 + (1 - F0) * (1 - (w_i • h))^5
// where F0 is the surface reflectance at zero incidence.
// https://en.wikipedia.org/wiki/Schlick%27s_approximation
//
float3 fresnelSchlick(float LdotH, float3 F0) {
	return F0 + (float3(1.0, 1.0, 1.0) - F0) * pow(1.0 - LdotH, 5.0);
}

//
// A variant of Schlick's approximation that takes a roughness "fudge factor".
// Meant to be used when computing the Fresnel factor on a prefiltered map (i.e.
// a color that is actually sampled from many directions, not just 1).
// https://seblagarde.wordpress.com/2011/08/17/hello-world/
//
float3 fresnelSchlickRoughness(float LdotV, float3 F0, float roughness) {
	float oneMinusRoughness = 1.0 - roughness;
	return F0 + (max(float3(oneMinusRoughness, oneMinusRoughness, oneMinusRoughness), F0) - F0) * pow(1.0 - LdotV, 5.0);
}

// Lighting
float3 calculateLightContribution(float3 lightDirection, float3 lightRadiance, float attenuation, float3 albedo, float3 normal, float roughness, float metallic, float3 viewDirection) {
	float3 halfVector = normalize(lightDirection + viewDirection);

	float3 F0 = float3(0.04, 0.04, 0.04);
	F0 = lerp(F0, albedo, metallic);

	float a = max(roughness * roughness, 0.002025);

	float NdotV = saturate(dot(normal, viewDirection));
	float NdotL = saturate(dot(normal, lightDirection));
	float NdotH = saturate(dot(normal, halfVector));
	float LdotH = saturate(dot(lightDirection, halfVector));

	float D = distributionGGX(NdotH, a);
	float3 F = fresnelSchlick(LdotH, F0);
	float V = visibilitySmithGGXCorrelated(NdotV, NdotL, a);

	// Specular BRDF
	float3 specular = (D * V) * F;

	// Diffuse BRDF (Lambertian)
	float3 diffuseColor = (1.0 - metallic) * albedo;
	float3 diffuse = diffuseColor / PI;

	return saturate((diffuse * lightRadiance + specular * lightRadiance) * NdotL * attenuation);
}

#endif // __PBR_HLSL__