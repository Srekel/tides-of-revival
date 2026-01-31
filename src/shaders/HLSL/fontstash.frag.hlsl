#define DIRECT3D12
#define STAGE_FRAG

#include "fontstash_resources.hlsli"
#include "utils.hlsli"

STRUCT(PsIn)
{
	DATA(float4, position, SV_Position);
	DATA(float2, texCoord, TEXCOORD0);
};

float4 PS_MAIN(PsIn In) : SV_TARGET
{
	INIT_MAIN;
	float4 Out;
	float4 linearColor = Get(color);

	// linearColor.rgb = sRGBToLinear_Float3(linearColor.rgb);
	linearColor.rgb = LinearTosRGB_Float3(linearColor.rgb);
	Out = float4(1.0, 1.0, 1.0, SampleTex2D(Get(uTex0), Get(uSampler0), In.texCoord).r) * linearColor;
	RETURN(Out);
}