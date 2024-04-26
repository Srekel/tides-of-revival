#define DIRECT3D12
#define STAGE_VERT

#include "im3d.hlsl"

CBUFFER(cbContextData, UPDATE_FREQ_PER_FRAME, b0, binding = 0)
{
    DATA(float4x4, uViewProjMatrix, None);
    DATA(float2, uViewport, None);
};

struct VS_INPUT
{
    float4 m_positionSize : POSITION; // POSITION_SIZE
    float4 m_color        : COLOR;
};

VS_OUTPUT VS_MAIN(VS_INPUT _in)
{
    INIT_MAIN;
    VS_OUTPUT Out;

    Out.m_color = _in.m_color.abgr; // swizzle to correct endianness
    Out.m_size = max(_in.m_positionSize.w, kAntialiasing);
    Out.m_position = mul(Get(uViewProjMatrix), float4(_in.m_positionSize.xyz, 1.0));

    RETURN(Out);
}
