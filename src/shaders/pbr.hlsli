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


// Adapted from Jakub Boksansky's "Crash Course in BRDF Implementation"

// Specifies minimal reflectance for dielectrics (when metalness is zero)
// Nothing has lower reflectance than 2%, but we use 4% to have consistent results with UE4, Frostbite, et al.
// Note: only takes effect when USE_REFLECTANCE_PARAMETER is not defined
#define MIN_DIELECTRICS_F0 0.04f

// Define this to use minimal reflectance (F0) specified per material, instead of global MIN_DIELECTRICS_F0 value
//#define USE_REFLECTANCE_PARAMETER 1

struct MaterialProperties
{
	float3 baseColor;
	float metalness;

	float3 emissive;
	float roughness;

	float transmissivness;
	float reflectance;		//< This should default to 0.5 to set minimal reflectance at 4%
	float opacity;
};

// Data needed to evaluate BRDF (surface and material properties at given point + configuration of light and normal vectors)
struct BrdfData
{
	// Material properties
	float3 specularF0;
	float3 diffuseReflectance;

	// Roughnesses
	float roughness;    //< perceptively linear roughness (artist's input)
	float alpha;        //< linear roughness - often 'alpha' in specular BRDF equations
	float alphaSquared; //< alpha squared - pre-calculated value commonly used in BRDF equations

	// Commonly used terms for BRDF evaluation
	float3 F; //< Fresnel term

	// Vectors
	float3 V; //< Direction to viewer
	float3 N; //< Shading normal
	float3 H; //< Half vector (microfacet normal)
	float3 L; //< Direction to light

	float NdotL;
	float NdotV;

	float LdotH;
	float NdotH;
	float VdotH;
};

float3 baseColorToSpecularF0(const float3 baseColor, const float metalness, const float reflectance = 0.5f) {
#if USE_REFLECTANCE_PARAMETER
	const float minDielectricsF0 = 0.16f * reflectance * reflectance;
#else
	const float minDielectricsF0 = MIN_DIELECTRICS_F0;
#endif
	return lerp(float3(minDielectricsF0, minDielectricsF0, minDielectricsF0), baseColor, metalness);
}

float3 baseColorToDiffuseReflectance(float3 baseColor, float metalness)
{
	return baseColor * (1.0f - metalness);
}

// -------------------------------------------------------------------------
//    Fresnel
// -------------------------------------------------------------------------

// Schlick's approximation to Fresnel term
// f90 should be 1.0, except for the trick used by Schuler (see 'shadowedF90' function)
float3 evalFresnelSchlick(float3 f0, float f90, float NdotS)
{
	return f0 + (f90 - f0) * pow(1.0f - NdotS, 5.0f);
}

// Attenuates F90 for very low F0 values
// Source: "An efficient and Physically Plausible Real-Time Shading Model" in ShaderX7 by Schuler
// Also see section "Overbright highlights" in Hoffman's 2010 "Crafting Physically Motivated Shading Models for Game Development" for discussion
// IMPORTANT: Note that when F0 is calculated using metalness, it's value is never less than MIN_DIELECTRICS_F0, and therefore,
// this adjustment has no effect. To be effective, F0 must be authored separately, or calculated in different way. See main text for discussion.
float shadowedF90(float3 F0) {
	// This scaler value is somewhat arbitrary, Schuler used 60 in his article. In here, we derive it from MIN_DIELECTRICS_F0 so
	// that it takes effect for any reflectance lower than least reflective dielectrics
	//const float t = 60.0f;
	const float t = (1.0f / MIN_DIELECTRICS_F0);
	return min(1.0f, t * luminance(F0));
}

// Precalculates commonly used terms in BRDF evaluation
// Clamps around dot products prevent NaNs and ensure numerical stability, but make sure to
BrdfData prepareBRDFData(float3 N, float3 L, float3 V, MaterialProperties material) {
	BrdfData data;

	// Evaluate VNHL vectors
	data.V = V;
	data.N = N;
	data.H = normalize(L + V);
	data.L = L;

	float NdotL = dot(N, L);
	float NdotV = dot(N, V);

	// Clamp NdotS to prevent numerical instability. Assume vectors below the hemisphere will be filtered using 'Vbackfacing' and 'Lbackfacing' flags
	data.NdotL = min(max(0.00001f, NdotL), 1.0f);
	data.NdotV = min(max(0.00001f, NdotV), 1.0f);

	data.LdotH = saturate(dot(L, data.H));
	data.NdotH = saturate(dot(N, data.H));
	data.VdotH = saturate(dot(V, data.H));

	// Unpack material properties
	data.specularF0 = baseColorToSpecularF0(material.baseColor, material.metalness, material.reflectance);
	data.diffuseReflectance = baseColorToDiffuseReflectance(material.baseColor, material.metalness);

	// Unpack 'perceptively linear' -> 'linear' -> 'squared' roughness
	data.roughness = material.roughness;
	data.alpha = material.roughness * material.roughness;
	data.alphaSquared = data.alpha * data.alpha;

	// Pre-calculate some more BRDF terms
	data.F = evalFresnelSchlick(data.specularF0, shadowedF90(data.specularF0), data.LdotH);

	return data;
}

float GGX_D(float alphaSquared, float NdotH) {
	float b = ((alphaSquared - 1.0f) * NdotH * NdotH + 1.0f);
	return alphaSquared / (PI * b * b);
}

// Smith G2 term (masking-shadowing function) for GGX distribution
// Height correlated version - optimized by substituing G_Lambda for G_Lambda_GGX and dividing by (4 * NdotL * NdotV) to cancel out
// the terms in specular BRDF denominator
// Source: "Moving Frostbite to Physically Based Rendering" by Lagarde & de Rousiers
// Note that returned value is G2 / (4 * NdotL * NdotV) and therefore includes division by specular BRDF denominator
float Smith_G2_Height_Correlated_GGX_Lagarde(float alphaSquared, float NdotL, float NdotV) {
	float a = NdotV * sqrt(alphaSquared + NdotL * (NdotL - alphaSquared * NdotL));
	float b = NdotL * sqrt(alphaSquared + NdotV * (NdotV - alphaSquared * NdotV));
	return 0.5f / (a + b);
}

// Frostbite's version of Disney diffuse with energy normalization.
// Source: "Moving Frostbite to Physically Based Rendering" by Lagarde & de Rousiers
float frostbiteDisneyDiffuse(const BrdfData data) {
	float energyBias = 0.5f * data.roughness;
	float energyFactor = lerp(1.0f, 1.0f / 1.51f, data.roughness);

	float FD90MinusOne = energyBias + 2.0 * data.LdotH * data.LdotH * data.roughness - 1.0f;

	float FDL = 1.0f + (FD90MinusOne * pow(1.0f - data.NdotL, 5.0f));
	float FDV = 1.0f + (FD90MinusOne * pow(1.0f - data.NdotV, 5.0f));

	return FDL * FDV * energyFactor;
}

float3 evalFrostbiteDisneyDiffuse(const BrdfData data) {
	return data.diffuseReflectance * (frostbiteDisneyDiffuse(data) * ONE_OVER_PI * data.NdotL);
}

float3 calculateLightContribution(float3 N, float3 L, float3 V, MaterialProperties material, float3 light_radiance, float attenuation)
{
	BrdfData brdf_data = prepareBRDFData(N, L, V, material);
	float3 F0 = float3(0.04, 0.04, 0.04);
	F0 = lerp(F0, material.baseColor, material.metalness);

	// Cook-Torrance BRDF
	float D = GGX_D(brdf_data.alphaSquared, brdf_data.NdotH);
	float G = Smith_G2_Height_Correlated_GGX_Lagarde(brdf_data.alphaSquared, brdf_data.NdotL, brdf_data.NdotV);

	float3 kS = brdf_data.F;
	float3 kD = float3(1.0, 1.0, 1.0) - kS;
	kD *= 1.0 - material.metalness;

	float3 specular = brdf_data.F * D * G * brdf_data.NdotL;
	float3 diffuse = evalFrostbiteDisneyDiffuse(brdf_data);

	return (kD * diffuse + specular) * light_radiance * brdf_data.NdotL * attenuation;
}

#endif // __PBR_HLSL__