#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "types.hlsli"

struct CullInstancesParams
{
    uint candidateMeshletsCountersBufferIndex;
    uint candidateMeshletsBufferIndex;
};

cbuffer g_Frame : register(b0, UPDATE_FREQ_PER_FRAME)
{
    Frame g_Frame;
}

cbuffer g_CullInstancesParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    CullInstancesParams g_CullInstancesParams;
};

Instance getInstance(uint instanceIndex)
{
    ByteAddressBuffer instanceBuffer = ResourceDescriptorHeap[g_Frame.instanceBufferIndex];
    Instance instance = instanceBuffer.Load<Instance>(instanceIndex * sizeof(Instance));
    return instance;
}

MaterialData getMaterial(uint materialIndex)
{
    ByteAddressBuffer materialBuffer = ResourceDescriptorHeap[g_Frame.materialBufferIndex];
    MaterialData material = materialBuffer.Load<MaterialData>(materialIndex * sizeof(MaterialData));
    return material;
}

bool FrustumCull(float3 aabbCenter, float3 aabbExtent, float4x4 world, float4x4 viewProj);

[numthreads(CULL_INSTANCES_THREADS_COUNT, 1, 1)] void main(uint DTid : SV_DispatchThreadID)
{
    RWByteAddressBuffer candidateMeshletsCountersBuffer = ResourceDescriptorHeap[g_CullInstancesParams.candidateMeshletsCountersBufferIndex];
    RWByteAddressBuffer candidateMeshletsBuffer = ResourceDescriptorHeap[g_CullInstancesParams.candidateMeshletsBufferIndex];
    uint instancesCount = g_Frame.instancesCount;

    if (DTid >= instancesCount)
    {
        return;
    }

    uint instanceIndex = DTid;
    Instance instance = getInstance(instanceIndex);

    ByteAddressBuffer mesh_buffer = ResourceDescriptorHeap[g_Frame.meshesBufferIndex];
    Mesh mesh = mesh_buffer.Load<Mesh>(instance.meshIndex * sizeof(Mesh));

    bool isVisible = FrustumCull(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world, g_Frame.viewProj);

    if (isVisible)
    {
        // Limit meshlet count to the buffer size
        // TODO: Set an out-of-memory flag to let the CPU know to grow the meshlet buffer
        uint globalMeshIndex;
        InterlockedAdd_Varying_WaveOps_ByteAddressBuffer(candidateMeshletsCountersBuffer, COUNTER_TOTAL_CANDIDATE_MESHLETS * sizeof(uint), mesh.meshletCount, globalMeshIndex);
        int clampedMeshletCount = min(globalMeshIndex + mesh.meshletCount, MESHLET_COUNT_MAX);
        int meshletsToAddCount = max(clampedMeshletCount - (int)globalMeshIndex, 0);

        // Add all meshlets of the current instance to the candidate meshlets buffer
        uint elementOffset;
        InterlockedAdd_Varying_WaveOps_ByteAddressBuffer(candidateMeshletsCountersBuffer, COUNTER_PHASE1_CANDIDATE_MESHLETS * sizeof(uint), meshletsToAddCount, elementOffset);

        for (uint i = 0; i < meshletsToAddCount; i++)
        {
            MeshletCandidate meshlet;
            meshlet.instanceId = instance.id;
            meshlet.meshletIndex = i;
            candidateMeshletsBuffer.Store<MeshletCandidate>((elementOffset + i) * sizeof(MeshletCandidate), meshlet);
        }
    }
}

bool FrustumCull(float3 aabbCenter, float3 aabbExtent, float4x4 world, float4x4 viewProj)
{
    bool isVisible = true;
    float4x4 mvp = mul(viewProj, world);

    float3 ext = aabbExtent * 2.0f;
    float4x4 extentsBasis = float4x4(
        ext.x, 0.0, 0.0, 0.0,
        0.0, ext.y, 0.0, 0.0,
        0.0, 0.0, ext.z, 0.0,
        0.0, 0.0, 0.0, 0.0);
    float4x4 axis = mul(mvp, extentsBasis);

    float4 corner000 = mul(mvp, float4(aabbCenter - aabbExtent, 1));
    float4 corner100 = corner000 + axis[0];
    float4 corner010 = corner000 + axis[1];
    float4 corner110 = corner010 + axis[0];
    float4 corner001 = corner000 + axis[2];
    float4 corner101 = corner100 + axis[2];
    float4 corner011 = corner010 + axis[2];
    float4 corner111 = corner110 + axis[2];

    float minW = min(corner000.w, corner001.w);
    minW = min(minW, corner010.w);
    minW = min(minW, corner011.w);
    minW = min(minW, corner100.w);
    minW = min(minW, corner101.w);
    minW = min(minW, corner110.w);
    minW = min(minW, corner111.w);

    float maxW = max(corner000.w, corner001.w);
    maxW = max(maxW, corner010.w);
    maxW = max(maxW, corner011.w);
    maxW = max(maxW, corner100.w);
    maxW = max(maxW, corner101.w);
    maxW = max(maxW, corner110.w);
    maxW = max(maxW, corner111.w);

    // Plane inequalities
    float4 planeMins = min(float4(corner000.xy, -corner000.xy) - corner000.w, float4(corner001.xy, -corner001.xy) - corner001.w);
    planeMins = min(planeMins, float4(corner010.xy, -corner010.xy) - corner010.w);
    planeMins = min(planeMins, float4(corner100.xy, -corner100.xy) - corner100.w);
    planeMins = min(planeMins, float4(corner110.xy, -corner110.xy) - corner110.w);
    planeMins = min(planeMins, float4(corner011.xy, -corner011.xy) - corner011.w);
    planeMins = min(planeMins, float4(corner101.xy, -corner101.xy) - corner101.w);
    planeMins = min(planeMins, float4(corner111.xy, -corner111.xy) - corner111.w);
    planeMins = min(planeMins, float4(1, 1, 1, 1));

    // Clip-space AABB
    float3 corner000Cs = corner000.xyz / corner000.w;
    float3 corner100Cs = corner100.xyz / corner100.w;
    float3 corner010Cs = corner010.xyz / corner010.w;
    float3 corner110Cs = corner110.xyz / corner110.w;
    float3 corner001Cs = corner001.xyz / corner001.w;
    float3 corner101Cs = corner101.xyz / corner101.w;
    float3 corner011Cs = corner011.xyz / corner011.w;
    float3 corner111Cs = corner111.xyz / corner111.w;

    float3 rectMin = min(corner000Cs, corner100Cs);
    rectMin = min(rectMin, corner010Cs);
    rectMin = min(rectMin, corner110Cs);
    rectMin = min(rectMin, corner001Cs);
    rectMin = min(rectMin, corner101Cs);
    rectMin = min(rectMin, corner011Cs);
    rectMin = min(rectMin, corner111Cs);
    rectMin = min(rectMin, float3(1, 1, 1));

    float3 rectMax = max(corner000Cs, corner100Cs);
    rectMax = max(rectMax, corner010Cs);
    rectMax = max(rectMax, corner110Cs);
    rectMax = max(rectMax, corner001Cs);
    rectMax = max(rectMax, corner101Cs);
    rectMax = max(rectMax, corner011Cs);
    rectMax = max(rectMax, corner111Cs);
    rectMax = max(rectMax, float3(1, 1, 1));

    isVisible &= rectMax.z > 0;

    if (minW <= 0 && maxW > 0)
    {
        rectMin = -1;
        rectMax = 1;
        isVisible = true;
    }
    else
    {
        isVisible &= maxW > 0.0f;
    }

    isVisible &= !any(planeMins > 0.0f);

    return isVisible;
}