#include "../../FSL/d3d.h"

RWTexture2D<float3> ColorRW : register(u0, UPDATE_FREQ_PER_FRAME);
SamplerState g_linear_clamp_edge_sampler : register(s0);

cbuffer CB0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float2 g_RcpBufferDim;
    float g_Radius;
    float g_Feather;
    float3 g_Color;
    float _padding0;
};

[numthreads(8, 8, 1)] void
main(uint3 DTid : SV_DispatchThreadID)
{
    float2 uv = (DTid.xy + 0.5) * g_RcpBufferDim * 2 - 1;
    float circle = length(uv);
    float mask = 1 - smoothstep(g_Radius, g_Radius + g_Feather, circle);
    float invMask = 1 - mask;

    float3 color = ColorRW[DTid.xy];
    float3 displayColor = color * mask;
    float3 vignetteColor = (1 - displayColor) * g_Color * invMask;

    ColorRW[DTid.xy] = displayColor + vignetteColor;
}
