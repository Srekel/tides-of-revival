#ifndef _MATERIAL_H
#define _MATERIAL_H

struct MaterialData
{
	float4 baseColor;
	float roughness;
	float metallic;
	float normalIntensity;
	float emissiveStrength;
	uint baseColorTextureIndex;
	uint emissiveTextureIndex;
	uint normalTextureIndex;
	uint armTextureIndex;
    uint windFeature;
    float windInitialBend;
    float windStifness;
    float windDrag;
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