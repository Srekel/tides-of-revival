#include "../../FSL/d3d.h"
#include "../SH.hlsli"

RWTexture2DArray<float4> skybox_cubemap : register(u0, UPDATE_FREQ_PER_FRAME);

cbuffer FrameBuffer : register(b0, UPDATE_FREQ_PER_FRAME)
{
    uint shCoefficientsBufferIndex;
    uint shCoefficientWeightsBufferIndex;
    uint shCoefficientsCount;
    uint faceIndex;
};

#define NUM_THREADS_X 16
#define NUM_THREADS_Y 16
#define CUBEMAP_RESOLUTION 64
#define CUBEMAP_RESOLUTION_INV 1.0f / 64.0f

groupshared SH::L2_RGB sh9[NUM_THREADS_X * NUM_THREADS_Y];
groupshared float weights[NUM_THREADS_X * NUM_THREADS_Y];

[numthreads(NUM_THREADS_X, NUM_THREADS_Y, 1)] void main(uint3 threadId : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID, uint3 Gid : SV_GroupID)
{
    static const float3x3 CUBEMAP_ROTATIONS[] =
        {
            float3x3(0, 0, -1, 0, -1, 0, -1, 0, 0), // right
            float3x3(0, 0, 1, 0, -1, 0, 1, 0, 0),   // left
            float3x3(1, 0, 0, 0, 0, -1, 0, 1, 0),   // top
            float3x3(1, 0, 0, 0, 0, 1, 0, -1, 0),   // bottom
            float3x3(1, 0, 0, 0, -1, 0, 0, 0, -1),  // back
            float3x3(-1, 0, 0, 0, -1, 0, 0, 0, 1),  // front
    };

    float2 uv = ((float2)threadId.xy + 0.5f) * CUBEMAP_RESOLUTION_INV;
    float3 dir = normalize(mul(CUBEMAP_ROTATIONS[faceIndex], float3(uv * 2 - 1, -1)));

    // Project the cubemap to onto SH coefficients
    // ===========================================
    float3 sky = skybox_cubemap[uint3(threadId.xy, faceIndex)].rgb;
    uint shIndex = GTid.x + GTid.y * NUM_THREADS_X;
    // Calculate SH contribution weight
    uv = uv * 2.0f - 1.0f;
    float temp = 1.0f + uv.x * uv.x + uv.y * uv.y;
    float weight = 4.0f / (sqrt(temp) * temp);
    sh9[shIndex] = SH::ProjectOntoL2(dir, sky) * weight;
    weights[shIndex] = weight;

    GroupMemoryBarrierWithGroupSync();

    RWByteAddressBuffer shCoefficientsBuffer = ResourceDescriptorHeap[shCoefficientsBufferIndex];
    RWByteAddressBuffer shCoefficientWeightsBuffer = ResourceDescriptorHeap[shCoefficientWeightsBufferIndex];
    uint groups = CUBEMAP_RESOLUTION / NUM_THREADS_X;
    uint groupCoeffIndex = (faceIndex * groups * groups) + (Gid.x + Gid.y * groups);

    if (GTid.x == 0 && GTid.y == 0)
    {
        SH::L2_RGB radianceSH = SH::L2_RGB::Zero();
        float weightSum = 0;
        for (uint i = 0; i < NUM_THREADS_X * NUM_THREADS_Y; i++)
        {
            radianceSH = radianceSH + sh9[i];
            weightSum += weights[i];
        }

        shCoefficientsBuffer.Store<SH::L2_RGB>(groupCoeffIndex * sizeof(SH::L2_RGB), radianceSH);
        shCoefficientWeightsBuffer.Store<float>(groupCoeffIndex * sizeof(float), weightSum);
    }
}