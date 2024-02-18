#define DIRECT3D12
#define STAGE_FRAG

#include "skybox_resources.hlsl"

float4 PS_MAIN( VSOutput Input ) : SV_TARGET0
{
	INIT_MAIN;
	float4 Out;
    Out = SampleTexCube(Get(skyboxTex), Get(skyboxSampler), Input.pos);

    RETURN(Out);
}
