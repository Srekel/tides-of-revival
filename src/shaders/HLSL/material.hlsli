#ifndef _MATERIAL_H
#define _MATERIAL_H

#define GRADIENT_COLORS_COUNT_MAX 8

struct MaterialData
{
	float4 albedoColor;
	float4 uvTilingOffset;
	float roughness;
	float metallic;
	float normalIntensity;
	float emissiveStrength;
	uint albedoTextureIndex;
	uint albedoSamplerIndex;
	uint emissiveTextureIndex;
	uint emissiveSamplerIndex;
	uint normalTextureIndex;
	uint normalSamplerIndex;
	uint armTextureIndex;
	uint armSamplerIndex;

	float randomColorFeatureEnabled;
	float randomColorNoiseScale;
	uint randomColorGradientTextureIndex;
	uint _pad0;

	uint rasterizerBin;
	uint3 _pad1;
};

#endif // _MATERIAL_H