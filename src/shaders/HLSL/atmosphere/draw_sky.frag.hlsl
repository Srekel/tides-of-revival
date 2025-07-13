#define DIRECT3D12
#define STAGE_FRAG

#include "draw_sky_resources.hlsli"

float4 PS_MAIN(VSOutput Input) : SV_Target
{
    float3 uv = normalize(Input.UV);
    return skybox_cubemap.Sample(g_linear_repeat_sampler, uv);
}