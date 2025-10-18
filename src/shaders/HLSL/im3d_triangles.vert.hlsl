// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#define DIRECT3D12
#define STAGE_VERT

#include "im3d.hlsli"

cbuffer cbContextData : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_view_proj_mat;
    float2 g_viewport;
}

struct VS_INPUT
{
    float4 m_positionSize : POSITION; // POSITION_SIZE
    float4 m_color : COLOR;
};

VS_OUTPUT VS_MAIN(VS_INPUT input)
{
    INIT_MAIN;
    VS_OUTPUT Out;

    Out.m_color = input.m_color.abgr; // swizzle to correct endianness
    Out.m_size = max(input.m_positionSize.w, kAntialiasing);
    Out.m_position = mul(g_view_proj_mat, float4(input.m_positionSize.xyz, 1.0));

    return Out;
}
