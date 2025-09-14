#define DIRECT3D12
#define STAGE_FRAG

#include "gpu_driven_gbuffer_resources.hlsli"

GBufferOutput PS_MAIN(VSOutput Input)
{
    INIT_MAIN;
    GBufferOutput Out;

    Out.GBuffer0 = float4(0.5f, 0.5f, 0.5f, 1.0f);
    Out.GBuffer1 = float4(0.0f, 1.0f, 0.0f, 1.0f);
    Out.GBuffer2 = float4(1.0f, 0.5f, 0.0f, 0.5f);

    RETURN(Out);
}
