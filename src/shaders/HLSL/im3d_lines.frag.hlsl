// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#define DIRECT3D12
#define STAGE_FRAG

#include "im3d.hlsli"

float4 VS_MAIN(VS_OUTPUT _in) : SV_TARGET
{
    INIT_MAIN;
    float4 ret = _in.m_color;

    float d = abs(_in.m_edgeDistance) / _in.m_size;
    d = smoothstep(1.0, 1.0 - (kAntialiasing / _in.m_size), d);
    ret.a *= d;

    RETURN(ret);
}
