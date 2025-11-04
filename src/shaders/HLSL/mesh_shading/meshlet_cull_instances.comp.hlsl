#include "meshlet_culling_common.hlsli"
#include "../debug_line_rendering.hlsli"

struct CullInstancesParams
{
    uint candidateMeshletsCountersBufferIndex;
    uint candidateMeshletsBufferIndex;
    uint shadowPass;
    float _padding;
};

cbuffer g_CullInstancesParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    CullInstancesParams g_CullInstancesParams;
};

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
    Instance2 instance = getInstance2(instanceIndex);

    ByteAddressBuffer meshBuffer = ResourceDescriptorHeap[g_Frame.meshesBufferIndex];

    ByteAddressBuffer renderableBuffer = ResourceDescriptorHeap[g_Frame.renderableMeshBufferIndex];
    RenderableMesh renderableMesh = renderableBuffer.Load<RenderableMesh>(instance.renderableMeshId * sizeof(RenderableMesh));

    // TODO
    bool isVisible = true;
    // // Distance-based LOD selection
    // float3 center = mul(float4(instance.localBoundsOrigin, 1.0), instance.world).xyz;
    // float distanceToCamera = max(0.01, length(center - g_Frame.cameraPosition.xyz));
    // bool isVisible = distanceToCamera >= instance.screenPercentageMin && distanceToCamera <= instance.screenPercentageMax;

    isVisible &= FrustumCull(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world, g_Frame.viewProj);

    if (isVisible)
    {
        // TODO
        // if (g_CullInstancesParams.shadowPass == 0)
        // {
        //     if (instance.flags & (1 << 1))
        //     {
        //         // DrawOBB(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world);
        //         // DrawAABB(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world, float4(1, 1, 1, 0.1));
        //         DrawBoundingSphere(instance.localBoundsOrigin, instance.localBoundsExtents, instance.world);
        //     }
        // }

        uint subMeshCount = renderableMesh.lods[0].subMeshesCount;
        for (uint smi = 0; smi < subMeshCount; smi++)
        {
            uint meshIndex = renderableMesh.lods[0].subMeshes[smi].meshIndex;
            uint materialIndex = renderableMesh.lods[0].subMeshes[smi].materialIndex;
            Mesh mesh = meshBuffer.Load<Mesh>(meshIndex * sizeof(Mesh));

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
                MeshletCandidate2 meshlet;
                meshlet.instanceId = instance.id;
                meshlet.meshIndex = meshIndex;
                meshlet.meshletIndex = i;
                meshlet.materialIndex = materialIndex;
                candidateMeshletsBuffer.Store<MeshletCandidate2>((elementOffset + i) * sizeof(MeshletCandidate2), meshlet);
            }
        }
    }
}