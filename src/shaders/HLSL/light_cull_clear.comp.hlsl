#include "../FSL/d3d.h"
#include "types.hlsli"

RWStructuredBuffer<uint> g_LightIndexCounter : register(u0, UPDATE_FREQ_PER_FRAME);

[numthreads(1, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    g_LightIndexCounter[0] = 0;
}