#ifndef _TYPES_HLSLI
#define _TYPES_HLSLI

struct BoundingBox
{
	float3 center;
	float3 extents;
};

struct GpuMeshData
{
	uint index_count;
	uint index_offset;
	uint vertex_count;
	uint vertex_offset;
	BoundingBox bounds;
};

struct InstanceData
{
	float4x4 worldMat;
	float4x4 worldMatInverted;
	uint materialIndex;
	float3 _padding;
};

struct InstanceIndirectionData
{
	uint instanceIndex;
	uint gpuMeshIndex;
	uint materialIndex;
	uint _padding;
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
	uint lod;
	uint2 _padding1;
};

struct GBufferOutput
{
	float4 GBuffer0 : SV_TARGET0;
	float4 GBuffer1 : SV_TARGET1;
	float4 GBuffer2 : SV_TARGET2;
};

struct GpuLight
{
	float3 position; // Direction for directional light
	uint light_type; // 0 - Directional, 1 - Point
	float3 color;
	float intensity;
	float radius; // Unused for directional light
	float shadow_intensity;
	float2 _padding;
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
	float3 NormalWS : NORMAL;
	float2 UV : TEXCOORD0;
	uint InstanceID : SV_InstanceID;
};

struct TerrainShadowVSOutput
{
	float4 Position : SV_Position;
	float2 UV : TEXCOORD0;
};

#endif // _TYPES_HLSLI