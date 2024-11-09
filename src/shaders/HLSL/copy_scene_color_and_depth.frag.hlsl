#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"

SamplerState g_linear_clamp_edge_sampler : register(s0, UPDATE_FREQ_NONE);

RES(Tex2D(float4), gBuffer2, UPDATE_FREQ_NONE, t5, binding = 9);
RES(Tex2D(float), depthBuffer, UPDATE_FREQ_NONE, t6, binding = 10);

Texture2D<float4> g_scene_color : register(t0, UPDATE_FREQ_PER_FRAME);
Texture2D<float> g_depth_buffer : register(t1, UPDATE_FREQ_PER_FRAME);

struct VsOut
{
    float4 Position : SV_Position;
    float2 UV : TEXCOORD0;
};

struct PsOut
{
    float4 m_scene_color : SV_TARGET0;
    float m_depth_buffer : SV_TARGET1;
};

PsOut PS_MAIN(VsOut input)
{
    PsOut output = (PsOut)0;
    output.m_scene_color = SampleLvlTex2D(g_scene_color, g_linear_clamp_edge_sampler, input.UV, 0);
    output.m_depth_buffer = SampleLvlTex2D(g_depth_buffer, g_linear_clamp_edge_sampler, input.UV, 0);

    return output;
}
