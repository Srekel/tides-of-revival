#include "meshlet_culling_common.hlsli"

struct CullInstancesParams
{
    uint candidateMeshletsCountersBufferIndex;
    uint candidateMeshletsBufferIndex;
};

cbuffer g_CullInstancesParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    CullInstancesParams g_CullInstancesParams;
};

// TODO
float CalculateScreenPercentage(float3 aabb_center, float3 aabb_extents, float4x4 world, float4x4 view_proj)
{
    return 0.1f;
}

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

    float screenPercentage = CalculateScreenPercentage(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world, g_Frame.viewProj);
    bool isVisible = screenPercentage >= instance.screenPercentageMin && screenPercentage < instance.screenPercentageMax;

    isVisible &= FrustumCull(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world, g_Frame.viewProj);

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