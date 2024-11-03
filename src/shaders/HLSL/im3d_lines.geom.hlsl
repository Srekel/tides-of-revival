// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#define DIRECT3D12
#define STAGE_GEOM

#include "im3d.hlsl"

cbuffer cbContextData : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_view_proj_mat;
    float2 g_viewport;
}

[maxvertexcount(4)]
void main(line VS_OUTPUT input[2], inout TriangleStream<VS_OUTPUT> output)
{
    float2 pos0 = input[0].m_position.xy / input[0].m_position.w;
    float2 pos1 = input[1].m_position.xy / input[1].m_position.w;

    float2 dir = pos0 - pos1;
    dir = normalize(float2(dir.x, dir.y * g_viewport.y / g_viewport.x)); // correct for aspect ratio
    float2 tng0 = float2(-dir.y, dir.x);
    float2 tng1 = tng0 * input[1].m_size / g_viewport;
    tng0 = tng0 * input[0].m_size / g_viewport;

    VS_OUTPUT ret;

    // line start
    ret.m_size = input[0].m_size;
    ret.m_color = input[0].m_color;
    ret.m_uv = float2(0.0, 0.0);
    ret.m_position = float4((pos0 - tng0) * input[0].m_position.w, input[0].m_position.zw);
    ret.m_edgeDistance = -input[0].m_size;
    output.Append(ret);
    ret.m_position = float4((pos0 + tng0) * input[0].m_position.w, input[0].m_position.zw);
    ret.m_edgeDistance = input[0].m_size;
    output.Append(ret);

    // line end
    ret.m_size = input[1].m_size;
    ret.m_color = input[1].m_color;
    ret.m_uv = float2(1.0, 1.0);
    ret.m_position = float4((pos1 - tng1) * input[1].m_position.w, input[1].m_position.zw);
    ret.m_edgeDistance = -input[1].m_size;
    output.Append(ret);
    ret.m_position = float4((pos1 + tng1) * input[1].m_position.w, input[1].m_position.zw);
    ret.m_edgeDistance = input[1].m_size;
    output.Append(ret);
}
