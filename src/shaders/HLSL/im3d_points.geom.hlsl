#define DIRECT3D12
#define STAGE_GEOM

#include "im3d.hlsl"

CBUFFER(cbContextData, UPDATE_FREQ_PER_FRAME, b0, binding = 0)
{
    DATA(float4x4, uViewProjMatrix, None);
    DATA(float2, uViewport, None);
};

[maxvertexcount(4)]
void main(point VS_OUTPUT _in[1], inout TriangleStream<VS_OUTPUT> out_)
{
    VS_OUTPUT ret;

    float2 scale = 1.0 / Get(uViewport) * _in[0].m_size;
    ret.m_size  = _in[0].m_size;
    ret.m_color = _in[0].m_color;
    ret.m_edgeDistance = _in[0].m_edgeDistance;

    ret.m_position = float4(_in[0].m_position.xy + float2(-1.0, -1.0) * scale * _in[0].m_position.w, _in[0].m_position.zw);
    ret.m_uv = float2(0.0, 0.0);
    out_.Append(ret);

    ret.m_position = float4(_in[0].m_position.xy + float2( 1.0, -1.0) * scale * _in[0].m_position.w, _in[0].m_position.zw);
    ret.m_uv = float2(1.0, 0.0);
    out_.Append(ret);

    ret.m_position = float4(_in[0].m_position.xy + float2(-1.0,  1.0) * scale * _in[0].m_position.w, _in[0].m_position.zw);
    ret.m_uv = float2(0.0, 1.0);
    out_.Append(ret);

    ret.m_position = float4(_in[0].m_position.xy + float2( 1.0,  1.0) * scale * _in[0].m_position.w, _in[0].m_position.zw);
    ret.m_uv = float2(1.0, 1.0);
    out_.Append(ret);
}
