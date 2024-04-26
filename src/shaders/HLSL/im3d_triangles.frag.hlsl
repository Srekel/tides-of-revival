#define DIRECT3D12
#define STAGE_FRAG

#include "im3d.hlsl"

float4 VS_MAIN(VS_OUTPUT _in) : SV_TARGET
{
    INIT_MAIN;
    float4 ret = _in.m_color;

    RETURN(ret);
}
