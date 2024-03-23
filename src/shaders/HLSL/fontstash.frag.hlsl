#define DIRECT3D12
#define STAGE_FRAG

#include "fontstash_resources.hlsl"

STRUCT(PsIn)
{
	DATA(float4, position, SV_Position);
	DATA(float2, texCoord, TEXCOORD0);
};

float4 PS_MAIN( PsIn In ) : SV_TARGET
{
	INIT_MAIN;
	float4 Out;
	Out = float4(1.0, 1.0, 1.0, SampleTex2D(Get(uTex0), Get(uSampler0), In.texCoord).r) * Get(color);
	RETURN(Out);
}