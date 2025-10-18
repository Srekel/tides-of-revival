#define DIRECT3D12
#define STAGE_FRAG

#include "skybox_resources.hlsli"
#include "utils.hlsli"

float4 PS_MAIN(VSOutput Input) : SV_TARGET0
{
    INIT_MAIN;
    float4 Out;
    Out = SampleTexCube(Get(skyboxMap), Get(g_linear_repeat_sampler), Input.pos);
    Out.rgb = sRGBToLinear_Float3(Out.rgb);

    RETURN(Out);
}
