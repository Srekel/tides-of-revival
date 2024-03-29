#define DIRECT3D12
#define STAGE_VERT

#include "fontstash_resources.hlsl"

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

PsIn VS_MAIN( VsIn In )
{
	INIT_MAIN;
	PsIn Out;
	Out.position = float4 (In.position, 0.0f, 1.0f);
	Out.position.xy = Out.position.xy * Get(scaleBias).xy + float2(-1.0f, 1.0f);
	Out.texCoord = In.texCoord;
	RETURN(Out);
}
