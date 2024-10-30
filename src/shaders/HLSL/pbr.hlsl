#ifndef _PBR_H
#define _PBR_H

struct PointLight
{
	float4 positionAndRadius;
	float4 colorAndIntensity;
};

struct DirectionalLight
{
	float4 directionAndShadowMap;
	float4 colorAndIntensity;
	float shadowRange;
	float _pad0;
	float _pad1;
	int shadowMapDimensions;
	float4x4 viewProj;
};

// The-Forge PBR Implementation
#ifndef PI
#define PI 3.141592653589f
#endif

#ifndef PI_DIV2
#define PI_DIV2 1.57079632679
#endif

//
// LIGHTING FUNCTIONS
//
float3 FresnelSchlickRoughness(float cosTheta, float3 F0, float roughness)
{
	float3 ret = float3(0.0, 0.0, 0.0);
	// pow(1.0 - cosTheta, 5.0)
	float x = 1.0 - cosTheta;
	// NOTE(gmodarelli): Replacing pow(x, 5.0) with 3 multiplies to avoid
	// generating nan in case cosTheta is > 1.0
	// 3 multiplies are also faster
	float powTheta = (x * x) * (x * x) * x;
	float invRough = float(1.0 - roughness);

	ret.x = F0.x + (max(invRough, F0.x) - F0.x) * powTheta;
	ret.y = F0.y + (max(invRough, F0.y) - F0.y) * powTheta;
	ret.z = F0.z + (max(invRough, F0.z) - F0.z) * powTheta;

	return ret;
}

float3 FresnelSchlick(float cosTheta, float3 F0)
{
	// pow(1.0 - cosTheta, 5.0)
	float x = 1.0 - cosTheta;
	// NOTE(gmodarelli): Replacing pow(x, 5.0) with 3 multiplies to avoid
	// generating nan in case cosTheta is > 1.0
	// 3 multiplies are also faster
	return F0 + (1.0f - F0) * ((x * x) * (x * x) * x);
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
	float a = roughness*roughness;
	float a2 = a*a;
	float NdotH = max(dot(N, H), 0.0);
	float NdotH2 = NdotH*NdotH;
	float nom = a2;
	float denom = (NdotH2 * (a2 - 1.0) + 1.0);
	denom = PI * denom * denom;

	return nom / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
	float r = (roughness + 1.0f);
	float k = (r*r) / 8.0f;

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

	float3 irradiance = SampleTexCube(Get(irradianceMap), Get(bilinearRepeatSampler), N).rgb;
	float3 specular = SampleLvlTexCube(Get(specularMap), Get(bilinearRepeatSampler), R, roughness * 4).rgb;

	float2 maxNVRough = float2(max(dot(N, V), 0.0), roughness);
	float2 brdf = SampleTex2D(Get(brdfIntegrationMap), Get(bilinearClampSampler), maxNVRough).rg;

	float3 Is = specular * (F * brdf.x + brdf.y);
	float3 Id = kD * irradiance * albedo;

	return Is + Id;
}

#endif // _PBR_H