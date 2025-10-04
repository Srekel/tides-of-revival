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

struct SurfaceInfo
{
	float3 normal;
	float3 position;
	float3 view;
	float3 albedo;
	float perceptual_roughness;
	float metallic;
	float reflectance;
};

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
	float k = roughness / max(0.00001f, (1.0 - NoH * NoH + a * a));
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
	return 0.5 / max(0.00001f, GGXV + GGXL);
}
//
// Approximation to remove the 2 sqrts. This is a mathematically wrong
float V_SmithGGXCorrelatedFast(float NoV, float NoL, float roughness)
{
	float a = roughness;
	float GGXV = NoL * (NoV * (1.0 - a) + a);
	float GGXL = NoV * (NoL * (1.0 - a) + a);
	return 0.5 / max(0.00001f, GGXV + GGXL);
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
float3 FilamentBRDF(float3 l, SurfaceInfo surfaceInfo)
{
	float3 h = normalize(surfaceInfo.normal + l);

	float NoV = abs(dot(surfaceInfo.normal, surfaceInfo.view)) + 1e-5;
	float NoL = clamp(dot(surfaceInfo.normal, l), 0.0, 1.0);
	float NoH = clamp(dot(surfaceInfo.normal, h), 0.0, 1.0);
	float LoH = clamp(dot(l, h), 0.0, 1.0);

	// Base color remapping
	float3 diffuse_color = (1.0f - surfaceInfo.metallic) * surfaceInfo.albedo;

	// Perceptually linear roughness to roughness
	float roughness = surfaceInfo.perceptual_roughness * surfaceInfo.perceptual_roughness;

	// Compute f0 for both dielectric and metallic materials
	float3 f0 = 0.16f * surfaceInfo.reflectance * surfaceInfo.reflectance * (1.0 - surfaceInfo.metallic) + surfaceInfo.albedo * surfaceInfo.metallic;

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

float3 ShadeDirectionalLight(GpuLight light, SurfaceInfo surfaceInfo, float shadowAttenuation)
{
	const float3 L = light.position;
	const float NdotL = max(dot(surfaceInfo.normal, L), 0.00001f);
	const float3 color = sRGBToLinear_Float3(light.color);
	const float3 radiance = color * light.intensity;

	const float3 brdf = FilamentBRDF(L, surfaceInfo);
	return brdf * radiance * NdotL * shadowAttenuation;
}

float3 ShadePointLight(GpuLight light, SurfaceInfo surfaceInfo, float shadowAttenuation)
{
	const float3 Pl = light.position;
	const float radius = light.radius;
	const float3 L = normalize(Pl - surfaceInfo.position);
	const float NdotL = max(dot(surfaceInfo.normal, L), 0.00001f);
	const float distance = length(Pl - surfaceInfo.position);
	const float attenuation = pow(saturate(1 - distance / radius), 2);

	const float3 color = sRGBToLinear_Float3(light.color);
	const float3 radiance = color * light.intensity * attenuation * 1;

	const float3 brdf = FilamentBRDF(L, surfaceInfo);
	return brdf * radiance * NdotL * shadowAttenuation;
}

float3 ShadeLight(GpuLight light, SurfaceInfo surfaceInfo, float shadowAttenuation)
{
	if (light.light_type == 0)
	{
		return ShadeDirectionalLight(light, surfaceInfo, shadowAttenuation);
	}
	else if (light.light_type == 1)
	{
		return ShadePointLight(light, surfaceInfo, shadowAttenuation);
	}

	return float3(1, 0, 1);
}

#endif // _PBR_H