// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#define DIRECT3D12
#define STAGE_GEOM

#include "im3d.hlsl"

CBUFFER(cbContextData, UPDATE_FREQ_PER_FRAME, b0, binding = 0)
{
    DATA(float4x4, uViewProjMatrix, None);
    DATA(float2, uViewport, None);
};

[maxvertexcount(4)]
void main(line VS_OUTPUT _in[2], inout TriangleStream<VS_OUTPUT> out_)
{
    float2 pos0 = _in[0].m_position.xy / _in[0].m_position.w;
    float2 pos1 = _in[1].m_position.xy / _in[1].m_position.w;

    float2 dir = pos0 - pos1;
    dir = normalize(float2(dir.x, dir.y * Get(uViewport).y / Get(uViewport).x)); // correct for aspect ratio
    float2 tng0 = float2(-dir.y, dir.x);
    float2 tng1 = tng0 * _in[1].m_size / Get(uViewport);
    tng0 = tng0 * _in[0].m_size / Get(uViewport);

    VS_OUTPUT ret;

    // line start
    ret.m_size = _in[0].m_size;
    ret.m_color = _in[0].m_color;
    ret.m_uv = float2(0.0, 0.0);
    ret.m_position = float4((pos0 - tng0) * _in[0].m_position.w, _in[0].m_position.zw);
    ret.m_edgeDistance = -_in[0].m_size;
    out_.Append(ret);
    ret.m_position = float4((pos0 + tng0) * _in[0].m_position.w, _in[0].m_position.zw);
    ret.m_edgeDistance = _in[0].m_size;
    out_.Append(ret);

    // line end
    ret.m_size = _in[1].m_size;
    ret.m_color = _in[1].m_color;
    ret.m_uv = float2(1.0, 1.0);
    ret.m_position = float4((pos1 - tng1) * _in[1].m_position.w, _in[1].m_position.zw);
    ret.m_edgeDistance = -_in[1].m_size;
    out_.Append(ret);
    ret.m_position = float4((pos1 + tng1) * _in[1].m_position.w, _in[1].m_position.zw);
    ret.m_edgeDistance = _in[1].m_size;
    out_.Append(ret);
}
