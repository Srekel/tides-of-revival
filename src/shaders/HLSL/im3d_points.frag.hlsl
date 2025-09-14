// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#define DIRECT3D12
#define STAGE_FRAG

#include "im3d.hlsli"

float4 VS_MAIN(VS_OUTPUT _in) : SV_TARGET
{
    INIT_MAIN;
    float4 ret = _in.m_color;

    float d = length(_in.m_uv - float2(0.5, 0.5));
    d = smoothstep(0.5, 0.5 - (kAntialiasing / _in.m_size), d);
    ret.a *= d;

    RETURN(ret);
}
