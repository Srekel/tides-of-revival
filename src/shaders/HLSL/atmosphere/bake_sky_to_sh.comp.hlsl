#include "../../FSL/d3d.h"
#include "../SH.hlsli"

Texture2DArray<float4> skybox_cubemap : register(t0, UPDATE_FREQ_PER_FRAME);

cbuffer FrameBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
    uint shCoefficientsBufferIndex;
    uint shCoefficientWeightsBufferIndex;
    uint shCoefficientsCount;
    uint sh9SkylightBufferIndex;
};

[numthreads(1, 1, 1)] void main()
{
    ByteAddressBuffer shCoefficientsBuffer = ResourceDescriptorHeap[shCoefficientsBufferIndex];
    ByteAddressBuffer shCoefficientWeightsBuffer = ResourceDescriptorHeap[shCoefficientWeightsBufferIndex];
    RWByteAddressBuffer sh9SkylightBuffer = ResourceDescriptorHeap[sh9SkylightBufferIndex];

    SH::L2_RGB radianceSH = SH::L2_RGB::Zero();
    float weightSum = 0.0f;

    for (uint i = 0; i < shCoefficientsCount; i++)
    {
        radianceSH = radianceSH + shCoefficientsBuffer.Load<SH::L2_RGB>(i * sizeof(SH::L2_RGB));
        weightSum += shCoefficientWeightsBuffer.Load<float>(i * sizeof(float));
    }

    radianceSH = radianceSH * (4.0f / 3.14159f) / weightSum;
    sh9SkylightBuffer.Store<SH::L2_RGB>(0, radianceSH);
}