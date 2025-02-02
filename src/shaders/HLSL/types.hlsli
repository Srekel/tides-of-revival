#ifndef _TYPES_HLSLI
#define _TYPES_HLSLI

struct InstanceData
{
	float4x4 worldMat;
	float4x4 worldMatInverted;
	uint materialBufferOffset;
	float3 _padding;
};

struct InstanceRootConstants
{
	uint startInstanceLocation;
	uint instanceDataBufferIndex;
	uint materialBufferIndex;
};

struct TerrainInstanceData
{
	float4x4 worldMat;
	uint heightmapTextureIndex;
	uint normalmapTextureIndex;
	uint lod;
	uint _padding1;
};

#endif // _TYPES_HLSLI