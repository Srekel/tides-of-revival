#include "../FSL/d3d.h"

RWByteAddressBuffer OutputBuffer : register(u0, UPDATE_FREQ_PER_FRAME);

[numthreads(32, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    OutputBuffer.Store(DTid.x * sizeof(uint), 0);
}