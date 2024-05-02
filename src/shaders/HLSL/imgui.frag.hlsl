#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

struct PS_INPUT
{
    float4 pos : SV_POSITION;
    float4 col : COLOR0;
    float2 uv  : TEXCOORD0;
};

RES(SamplerState, sampler0, UPDATE_FREQ_NONE, s0, binding = 0);
RES(Tex2D(float4), texture0, UPDATE_FREQ_PER_FRAME, t0, binding = 1);

float4 main(PS_INPUT input) : SV_Target
{
    INIT_MAIN;
    
    float4 out_col = input.col * texture0.Sample(sampler0, input.uv); 
    return out_col; 
}
