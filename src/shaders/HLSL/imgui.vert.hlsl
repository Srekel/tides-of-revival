#define DIRECT3D12
#define STAGE_VERT

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

cbuffer RootConstant : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float4x4 g_proj_mat;
};

struct VS_INPUT
{
  float2 pos : POSITION;
  float2 uv  : TEXCOORD0;
  float4 col : COLOR0;
};

struct PS_INPUT
{
  float4 pos : SV_POSITION;
  float4 col : COLOR0;
  float2 uv  : TEXCOORD0;
};

PS_INPUT main(VS_INPUT input)
{
    INIT_MAIN;

    PS_INPUT output;
    output.pos = mul( g_proj_mat, float4(input.pos.xy, 0.f, 1.f));
    output.col = input.col;
    output.uv  = input.uv;
    return output;
}
