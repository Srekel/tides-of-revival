#ifndef _PBR_H
#define _PBR_H

#include "types.hlsli"
#include "utils.hlsli"

// The-Forge PBR Implementation
#ifndef PI
#define PI 3.141592653589f
#endif

#ifndef INV_PI
#define INV_PI 1.0f / 3.141592653589f
#endif

#ifndef PI_DIV2
#define PI_DIV2 1.57079632679
#endif

// ███████╗██╗██╗      █████╗ ███╗   ███╗███████╗███╗   ██╗████████╗    ██████╗ ██████╗ ██████╗
// ██╔════╝██║██║     ██╔══██╗████╗ ████║██╔════╝████╗  ██║╚══██╔══╝    ██╔══██╗██╔══██╗██╔══██╗
// █████╗  ██║██║     ███████║██╔████╔██║█████╗  ██╔██╗ ██║   ██║       ██████╔╝██████╔╝██████╔╝
// ██╔══╝  ██║██║     ██╔══██║██║╚██╔╝██║██╔══╝  ██║╚██╗██║   ██║       ██╔═══╝ ██╔══██╗██╔══██╗
// ██║     ██║███████╗██║  ██║██║ ╚═╝ ██║███████╗██║ ╚████║   ██║       ██║     ██████╔╝██║  ██║
// ╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝╚═╝  ╚═══╝   ╚═╝       ╚═╝     ╚═════╝ ╚═╝  ╚═╝
//
// Normal Distribution function (specular D)
// =========================================
// GGX Distribution from [Walter07]
// Bruce Walter et al. 2007. Microfacet Models for Refraction through Rough Surfaces. Proceedings of the Eurographics Symposium on Rendering
float D_GGX(float NoH, float roughness)
{
	float a = NoH * roughness;
	float k = roughness / (1.0 - NoH * NoH + a * a);
	return k * k * (1.0 / PI);
}
//
// Geometric shadowing (specular G)
// ================================
// Smith height-correlated GGX from [Heitz14]
// Eric Heitz. 2014. Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs. Journal of Computer Graphics Techniques, 3 (2)
float V_SmithGGXCorrelated(float NoV, float NoL, float roughness)
{
	float a2 = roughness * roughness;
	float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
	float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
	return 0.5 / (GGXV + GGXL);
}
//
// Approximation to remove the 2 sqrts. This is a mathematically wrong
float V_SmithGGXCorrelatedFast(float NoV, float NoL, float roughness)
{
	float a = roughness;
	float GGXV = NoL * (NoV * (1.0 - a) + a);
	float GGXL = NoV * (NoL * (1.0 - a) + a);
	return 0.5 / (GGXV + GGXL);
}
//
// Fresnel (specular F)
// ====================
// [Schlick94] Implementation of the Fresnel term
// Christophe Schlick. 1994. An Inexpensive BRDF Model for Physically-Based Rendering. Computer Graphics Forum, 13 (3), 233–246
float3 F_Schlick(float u, float3 f0, float f90)
{
	return f0 + (float3(f90.xxx) - f0) * pow5(1.0 - u);
}
//
float F_Schlick(float u, float f0, float f90)
{
	return f0 + (f90 - f0) * pow5(1.0 - u);
}
//
// Diffuse BRDF
// ============
// Lambertian BRDF
float Fd_Lambert()
{
	return INV_PI;
}
//
// Disney diffuse BRDF from [Burley12]
// Brent Burley. 2012. Physically Based Shading at Disney. Physically Based Shading in Film and Game Production, ACM SIGGRAPH 2012 Courses
float Fd_Burley(float NoV, float NoL, float LoH, float roughness)
{
	float f90 = 0.5 + 2.0 * roughness * LoH * LoH;
	float light_scatter = F_Schlick(NoL, 1.0, f90);
	float view_scatter = F_Schlick(NoV, 1.0, f90);
	return light_scatter * view_scatter * INV_PI;
}
//
// BRDF
// ====
// NOTE: Reflectance values for various types of materials are available at the following link
// https://google.github.io/filament/Filament.md.html#table_commonmatreflectance
float3 FilamentBRDF(float3 n, float3 v, float3 l, float3 albedo, float perceptual_roughness, float metallic, float reflectance)
{
	float3 h = normalize(v + l);

	float NoV = abs(dot(n, v)) + 1e-5;
	float NoL = clamp(dot(n, l), 0.0, 1.0);
	float NoH = clamp(dot(n, h), 0.0, 1.0);
	float LoH = clamp(dot(l, h), 0.0, 1.0);

	// Base color remapping
	float3 diffuse_color = (1.0f - metallic) * albedo;

	// Perceptually linear roughness to roughness
	float roughness = perceptual_roughness * perceptual_roughness;

	// Compute f0 for both dielectric and metallic materials
	float3 f0 = 0.16f * reflectance * reflectance * (1.0 - metallic) + albedo * metallic;

	float D = D_GGX(NoH, roughness);
	float3 F = F_Schlick(LoH, f0, 1.0f);
	float V = V_SmithGGXCorrelated(NoV, NoL, roughness);

	// Specular BRDF
	float3 Fr = (D * V) * F;

	// Diffuse BRDF
	float3 Fd = diffuse_color * Fd_Lambert();

	// TODO: Add energy conservation
	return Fd + (Fr * 0.1f);
}

//  ██████╗ ██╗     ██████╗     ██████╗ ██████╗ ██████╗
// ██╔═══██╗██║     ██╔══██╗    ██╔══██╗██╔══██╗██╔══██╗
// ██║   ██║██║     ██║  ██║    ██████╔╝██████╔╝██████╔╝
// ██║   ██║██║     ██║  ██║    ██╔═══╝ ██╔══██╗██╔══██╗
// ╚██████╔╝███████╗██████╔╝    ██║     ██████╔╝██║  ██║
//  ╚═════╝ ╚══════╝╚═════╝     ╚═╝     ╚═════╝ ╚═╝  ╚═╝
//

//
// LIGHTING FUNCTIONS
//
float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
	float3 ret = float3(0.0, 0.0, 0.0);
	float powTheta = pow5(1.0 - cosTheta);
	float invRough = float(1.0 - roughness);

	ret.x = F0.x + (max(invRough, F0.x) - F0.x) * powTheta;
	ret.y = F0.y + (max(invRough, F0.y) - F0.y) * powTheta;
	ret.z = F0.z + (max(invRough, F0.z) - F0.z) * powTheta;

	return ret;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
	return F0 + (1.0f - F0) * pow5(1.0 - cosTheta);
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
	float a = roughness * roughness;
	float a2 = a * a;
	float NdotH = max(dot(N, H), 0.0);
	float NdotH2 = NdotH * NdotH;
	float nom = a2;
	float denom = (NdotH2 * (a2 - 1.0) + 1.0);
	denom = PI * denom * denom;

	return nom / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
	float r = (roughness + 1.0f);
	float k = (r * r) / 8.0f;

	float nom = NdotV;
	float denom = NdotV * (1.0 - k) + k;

	return nom / denom;
}

float GeometrySmith(float3 N, float3 V, float3 L, float roughness)
{
	float NdotV = max(dot(N, V), 0.0);
	float NdotL = max(dot(N, L), 0.0);
	float ggx2 = GeometrySchlickGGX(NdotV, roughness);
	float ggx1 = GeometrySchlickGGX(NdotL, roughness);

	return ggx1 * ggx2;
}

float3 LambertDiffuse(float3 albedo, float3 kD)
{
	return kD * albedo / PI;
}

float3 BRDF(float3 N, float3 V, float3 L, float3 albedo, float roughness, float metalness)
{
	const float3 H = normalize(V + L);

	// F0 represents the base reflectivity (calculated using IOR: index of refraction)
	float3 F0 = float3(0.04f, 0.04f, 0.04f);
	F0 = lerp(F0, albedo, metalness);

	float NDF = DistributionGGX(N, H, roughness);
	float G = GeometrySmith(N, V, L, roughness);
	float3 F = FresnelSchlick(max(dot(N, H), 0.0f), F0);

	float3 kS = F;
	float3 kD = (float3(1.0f, 1.0f, 1.0f) - kS) * (1.0f - metalness);

	float3 Is = NDF * G * F / (4.0f * max(dot(N, V), 0.0f) * max(dot(N, L), 0.0f) + 0.001f);
	float3 Id = LambertDiffuse(albedo, kD);

	return Id + Is;
}

float3 EnvironmentBRDF(float3 N, float3 V, float3 albedo, float roughness, float metalness)
{
	const float3 R = reflect(-V, N);

	// F0 represents the base reflectivity (calculated using IOR: index of refraction)
	float3 F0 = float3(0.04f, 0.04f, 0.04f);
	F0 = lerp(F0, albedo, metalness);

	float3 F = FresnelSchlickRoughness(max(dot(N, V), 0.0f), F0, roughness);

	float3 kS = F;
	float3 kD = (float3(1.0f, 1.0f, 1.0f) - kS) * (1.0f - metalness);

	float3 irradiance = SampleTexCube(g_irradiance_map, Get(g_linear_repeat_sampler), N).rgb;
	float3 specular = SampleLvlTexCube(g_specular_map, Get(g_linear_repeat_sampler), R, roughness * 4).rgb;

	float2 maxNVRough = float2(max(dot(N, V), 0.0), roughness);
	float2 brdf = SampleTex2D(g_brdf_integration_map, Get(g_linear_clamp_edge_sampler), maxNVRough).rg;

	float3 Is = specular * (F * brdf.x + brdf.y);
	float3 Id = kD * irradiance * max(float3(0.04, 0.04, 0.04), albedo);

	// TODO: Implement energy conservation
	return (Is * 0.1) + Id;
}

#endif // _PBR_H