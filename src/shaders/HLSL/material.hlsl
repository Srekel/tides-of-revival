#ifndef _MATERIAL_H
#define _MATERIAL_H

struct MaterialData
{
	// Surface
	float4 baseColor;
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
	// Wind Feature
    uint windFeature;
    float windInitialBend;
    float windStifness;
    float windDrag;
	// Wind Shiver Feature
    uint windShiverFeature;
    float windShiverDrag;
    float windNormalInfluence;
    float windShiverDirectionality;
};

static const uint INVALID_TEXTURE_INDEX = 0xFFFFFFFF;

bool hasValidTexture(uint textureIndex)
{
	return textureIndex != INVALID_TEXTURE_INDEX;
}

#endif // _MATERIAL_H