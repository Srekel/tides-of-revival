#define DIRECT3D12
#define STAGE_FRAG

#include "skybox_resources.hlsl"
#include "utils.hlsl"

float4 PS_MAIN( VSOutput Input ) : SV_TARGET0
{
	INIT_MAIN;
	float4 Out;
    Out = SampleTexCube(Get(skyboxMap), Get(bilinearRepeatSampler), Input.pos);
    Out.rgb = srgb_to_linear_float3(Out.rgb);

    RETURN(Out);
}
