#include "gpu_culling_resources.hlsli"

[numthreads(64, 1, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    ByteAddressBuffer instanceBuffer = ResourceDescriptorHeap[g_InstanceBufferIndex];
    ByteAddressBuffer instanceIndirectionBuffer = ResourceDescriptorHeap[g_InstanceIndirectionBufferIndex];
    ByteAddressBuffer gpuMeshBuffer = ResourceDescriptorHeap[g_GpuMeshBufferIndex];

    RWByteAddressBuffer countersBuffer = ResourceDescriptorHeap[g_CountersBufferIndex];
    RWByteAddressBuffer visibleInstanceIndirectionBuffer = ResourceDescriptorHeap[g_VisibleInstanceIndirectionBufferIndex];

    if (DTid.x < g_InstanceIndirectionCount)
    {
        InstanceIndirectionData instanceIndirectionData = instanceIndirectionBuffer.Load<InstanceIndirectionData>(DTid.x * sizeof(InstanceIndirectionData));
        InstanceData instanceData = instanceBuffer.Load<InstanceData>(instanceIndirectionData.instanceIndex);
        GpuMeshData gpuMeshData = gpuMeshBuffer.Load<GpuMeshData>(instanceIndirectionData.gpuMeshIndex * sizeof(GpuMeshData));

        if (FrustumCull(gpuMeshData.bounds.center, gpuMeshData.bounds.extents, instanceData.worldMat, g_ViewProj))
        {
            uint visibleInstanceIndex;
            countersBuffer.InterlockedAdd(COUNTER_VISIBLE_INSTANCE_INDEX, 1, visibleInstanceIndex);

            visibleInstanceIndirectionBuffer.Store<InstanceIndirectionData>(visibleInstanceIndex * sizeof(InstanceIndirectionData), instanceIndirectionData);
        }
    }
}