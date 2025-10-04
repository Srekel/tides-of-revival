#ifndef _MATERIAL_H
#define _MATERIAL_H

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
	uint rasterizerBin;
	uint3 _pad0;
};

#endif // _MATERIAL_H