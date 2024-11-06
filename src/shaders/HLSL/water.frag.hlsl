#define DIRECT3D12
#define STAGE_FRAG

#include "water_resources.hlsl"

float4 PS_MAIN(VSOutput Input) : SV_TARGET0 {
    return float4(1, 1, 1, 1);
}