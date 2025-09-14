#define DIRECT3D12
#define STAGE_VERT

#include "fontstash_resources.hlsli"

STRUCT(VsIn)
{
	DATA(float2, position, Position);
	DATA(float2, texCoord, TEXCOORD0);
};

STRUCT(PsIn)
{
	DATA(float4, position, SV_Position);
	DATA(float2, texCoord, TEXCOORD0);
};

PsIn VS_MAIN(VsIn In)
{
	INIT_MAIN;

#if FT_MULTIVIEW
	float4x4 modelViewProj = Get(mvp)[VR_VIEW_ID];
#else
	float4x4 modelViewProj = Get(mvp);
#endif

	PsIn Out;
	Out.position = mul(modelViewProj, float4(In.position * Get(scaleBias).xy, 1.0f, 1.0f));
	Out.texCoord = In.texCoord;
	RETURN(Out);
}