#include "meshlet_binning_common.hlsli"

[numthreads(64, 1, 1)] void main(uint DTid : SV_DispatchThreadID)
{
    RWByteAddressBuffer globalMeshletCountBuffer = ResourceDescriptorHeap[g_BinningParams.globalMeshletCounterBufferIndex];
    RWByteAddressBuffer meshletOffsetAndCountsBuffer = ResourceDescriptorHeap[g_BinningParams.meshletOffsetAndCountsBufferIndex];
    RWByteAddressBuffer binnedMeshletsBuffer = ResourceDescriptorHeap[g_BinningParams.binnedMeshletsBufferIndex];

    uint meshletIndex = DTid;
    if (meshletIndex >= GetMeshletsCount())
        return;

    uint bin = GetBin(meshletIndex);

    uint offset = meshletOffsetAndCountsBuffer.Load<uint4>(bin * sizeof(uint4)).w;
    uint meshletOffset;

    // WaveOps optimzed loop to write meshlet indices to its associated bins.

    // Loop until all meshlets have their indices written
    bool finished = false;
    while (WaveActiveAnyTrue(!finished))
    {
        // Mask out all threads which are already finished
        if (!finished)
        {
            // Get the bin of the first thread
            const uint firstBin = WaveReadLaneFirst(bin);
            if (firstBin == bin)
            {
                // All threads which have the same bin as the first active lane writes its index
                uint originalValue;
                uint count = WaveActiveCountBits(true);
                if (WaveIsFirstLane())
                    meshletOffsetAndCountsBuffer.InterlockedAdd(firstBin * sizeof(uint4), count, originalValue);
                meshletOffset = WaveReadLaneFirst(originalValue) + WavePrefixCountBits(true);
                finished = true;
            }
        }
    }

    binnedMeshletsBuffer.Store<uint>((offset + meshletOffset) * sizeof(uint), meshletIndex);
}