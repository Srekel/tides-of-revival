#include "../../FSL/d3d.h"
#include "../SH.hlsli"

cbuffer FrameBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
    uint shCoefficientsBufferIndex;
    uint shCoefficientWeightsBufferIndex;
    uint shCoefficientsCount;
    uint _pad0;
};

[numthreads(1, 1, 1)] void main(uint3 threadId : SV_DispatchThreadID)
{
    RWByteAddressBuffer shCoefficientsBuffer = ResourceDescriptorHeap[shCoefficientsBufferIndex];
    RWByteAddressBuffer shCoefficientWeightsBuffer = ResourceDescriptorHeap[shCoefficientWeightsBufferIndex];

    SH::L2_RGB radianceSH = SH::L2_RGB::Zero();
    float weightSum = 0.0f;

    for (uint i = 0; i < shCoefficientsCount; i++)
    {
        radianceSH = radianceSH + shCoefficientsBuffer.Load<SH::L2_RGB>(i * sizeof(SH::L2_RGB));
        weightSum += shCoefficientWeightsBuffer.Load<float>(i * sizeof(float));
    }

    radianceSH = radianceSH * (4.0f / 3.14159f) / weightSum;
    shCoefficientsBuffer.Store<SH::L2_RGB>(0, radianceSH);
}