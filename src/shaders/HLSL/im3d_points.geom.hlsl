// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#define DIRECT3D12
#define STAGE_GEOM

#include "im3d.hlsli"

cbuffer cbContextData : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_view_proj_mat;
    float2 g_viewport;
}

[maxvertexcount(4)] void main(point VS_OUTPUT input[1], inout TriangleStream<VS_OUTPUT> output)
{
    VS_OUTPUT ret;

    float2 scale = 1.0 / g_viewport * input[0].m_size;
    ret.m_size = input[0].m_size;
    ret.m_color = input[0].m_color;
    ret.m_edgeDistance = input[0].m_edgeDistance;

    ret.m_position = float4(input[0].m_position.xy + float2(-1.0, -1.0) * scale * input[0].m_position.w, input[0].m_position.zw);
    ret.m_uv = float2(0.0, 0.0);
    output.Append(ret);

    ret.m_position = float4(input[0].m_position.xy + float2(1.0, -1.0) * scale * input[0].m_position.w, input[0].m_position.zw);
    ret.m_uv = float2(1.0, 0.0);
    output.Append(ret);

    ret.m_position = float4(input[0].m_position.xy + float2(-1.0, 1.0) * scale * input[0].m_position.w, input[0].m_position.zw);
    ret.m_uv = float2(0.0, 1.0);
    output.Append(ret);

    ret.m_position = float4(input[0].m_position.xy + float2(1.0, 1.0) * scale * input[0].m_position.w, input[0].m_position.zw);
    ret.m_uv = float2(1.0, 1.0);
    output.Append(ret);
}
