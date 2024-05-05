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
    bool wind_feature;
    float wind_initial_bend;
    float wind_stifness;
    float wind_drag;
    bool wind_shiver_feature;
    float wind_shiver_drag;
    float wind_normal_influence;
    float wind_shiver_directionality;
};

static const uint INVALID_TEXTURE_INDEX = 0xFFFFFFFF;

bool hasValidTexture(uint textureIndex)
{
	return textureIndex != INVALID_TEXTURE_INDEX;
}

#endif // _MATERIAL_H