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

struct GBufferOutput
{
	float4 GBuffer0 : SV_TARGET0;
	float4 GBuffer1 : SV_TARGET1;
	float4 GBuffer2 : SV_TARGET2;
};

// NOTE: We will get rid of these once we stop using InputLayouts for our PSOs.
// We currently depend on The-Forge asset pipeline which makes use of InputLayouts
// when loading a mesh from file.

#if defined(VL_PosNorTanUv0Col)

struct VSInput
{
	float4 Position : POSITION;
	float3 Normal : NORMAL;
	float4 Tangent : TANGENT;
	float2 UV : TEXCOORD0;
	float4 Color : COLOR;
};

struct VSOutput
{
	float4 Position : SV_Position;
	float3 PositionWS : POSITION;
	float3 Normal : NORMAL;
	float4 Tangent : TANGENT;
	float2 UV : TEXCOORD0;
	float4 Color : COLOR;
	uint InstanceID : SV_InstanceID;
};

struct ShadowVSOutput
{
	float4 Position : SV_Position;
	float2 UV : TEXCOORD0;
	uint InstanceID : SV_InstanceID;
};

#elif defined(VL_PosNorTanUv0ColUv1)

struct VSInput
{
	float4 Position : POSITION;
	float3 Normal : NORMAL;
	float4 Tangent : TANGENT;
	float2 UV : TEXCOORD0;
	float4 Color : COLOR;
	float2 UV1 : TEXCOORD1;
};

struct VSOutput
{
	float4 Position : SV_Position;
	float3 PositionWS : POSITION;
	float3 Normal : NORMAL;
	float4 Tangent : TANGENT;
	float2 UV : TEXCOORD0;
	float4 Color : COLOR;
	float2 UV1 : TEXCOORD1;
	uint InstanceID : SV_InstanceID;
};

struct ShadowVSOutput
{
	float4 Position : SV_Position;
	float2 UV : TEXCOORD0;
    float2 UV1 : TEXCOORD1;
	uint InstanceID : SV_InstanceID;
};

#endif

struct TerrainVSInput
{
	float4 Position : POSITION;
	float2 UV : TEXCOORD0;
	float4 Color : COLOR;
};

struct TerrainVSOutput
{
	float4 Position : SV_Position;
	float3 PositionWS : POSITION;
	float2 UV : TEXCOORD0;
	float3 Normal : TEXCOORD1;
	uint InstanceID : SV_InstanceID;
};

struct TerrainShadowVSOutput
{
	float4 Position : SV_Position;
	float2 UV : TEXCOORD0;
};

#endif // _TYPES_HLSLI