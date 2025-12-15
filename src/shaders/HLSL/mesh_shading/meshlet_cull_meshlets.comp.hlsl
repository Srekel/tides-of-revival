#include "meshlet_culling_common.hlsli"

struct CullMeshletsParams
{
    uint candidateMeshletsCountersBufferIndex;
    uint candidateMeshletsBufferIndex;
    uint visibleMeshletsCountersBufferIndex;
    uint visibleMeshletsBufferIndex;
};

cbuffer g_CullMeshletsParams : register(b1, UPDATE_FREQ_PER_FRAME)
{
    CullMeshletsParams g_CullMeshletsParams;
};

[numthreads(CULL_INSTANCES_THREADS_COUNT, 1, 1)] void main(uint DTid : SV_DispatchThreadID)
{
    RWByteAddressBuffer candidateMeshletsCountersBuffer = ResourceDescriptorHeap[g_CullMeshletsParams.candidateMeshletsCountersBufferIndex];
    RWByteAddressBuffer visibleMeshletsCountersBuffer = ResourceDescriptorHeap[g_CullMeshletsParams.visibleMeshletsCountersBufferIndex];
    RWByteAddressBuffer candidateMeshletsBuffer = ResourceDescriptorHeap[g_CullMeshletsParams.candidateMeshletsBufferIndex];
    RWByteAddressBuffer visibleMeshletsBuffer = ResourceDescriptorHeap[g_CullMeshletsParams.visibleMeshletsBufferIndex];

    if (DTid < candidateMeshletsCountersBuffer.Load<uint>(COUNTER_PHASE1_CANDIDATE_MESHLETS * sizeof(uint)))
    {
        uint candidate_index = DTid;
        MeshletCandidate candidate = candidateMeshletsBuffer.Load<MeshletCandidate>(candidate_index * sizeof(MeshletCandidate));
        Instance instance = getInstance(candidate.instanceId);

        ByteAddressBuffer mesh_buffer = ResourceDescriptorHeap[g_Frame.meshesBufferIndex];
        Mesh mesh = mesh_buffer.Load<Mesh>(candidate.meshIndex * sizeof(Mesh));

        ByteAddressBuffer data_buffer = ResourceDescriptorHeap[NonUniformResourceIndex(mesh.dataBufferIndex)];
        MeshletBounds bounds = data_buffer.Load<MeshletBounds>(candidate.meshletIndex * sizeof(MeshletBounds) + mesh.meshletBoundsOffset);
        bool is_visible = FrustumCull(bounds.localCenter, bounds.localExtents, instance.world, g_Frame.viewProj);

        if (is_visible)
        {
            uint elementOffset;
            InterlockedAdd_WaveOps_ByteAddressBuffer(visibleMeshletsCountersBuffer, COUNTER_PHASE1_VISIBLE_MESHLETS * sizeof(uint), 1, elementOffset);
            visibleMeshletsBuffer.Store<MeshletCandidate>(elementOffset * sizeof(MeshletCandidate), candidate);
        }
    }
}