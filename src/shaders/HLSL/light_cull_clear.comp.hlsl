#include "../FSL/d3d.h"
#include "types.hlsli"

RWByteAddressBuffer g_VisibleLightsCountBuffer : register(u0, UPDATE_FREQ_PER_FRAME);

[numthreads(1, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    g_VisibleLightsCountBuffer.Store<uint>(0, 0);
}