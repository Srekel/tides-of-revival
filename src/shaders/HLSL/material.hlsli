#ifndef _MATERIAL_H
#define _MATERIAL_H

struct MaterialData
{
	// Surface
	float4 baseColor;
	float4 uvTilingOffset;
	float roughness;
	float metallic;
	float normalIntensity;
	float emissiveStrength;
	uint baseColorTextureIndex;
	uint emissiveTextureIndex;
	uint normalTextureIndex;
	uint armTextureIndex;
	// Details
	uint detailFeature;
	uint detailMaskTextureIndex;
	uint detailBaseColorTextureIndex;
	uint detailNormalTextureIndex;
	uint detailArmTextureIndex;
	uint detailUseUV2;
};

#endif // _MATERIAL_H