#include "meshlet_binning_common.hlsli"

[numthreads(64, 1, 1)] void main(uint DTid : SV_DispatchThreadID)
{
    uint meshletIndex = DTid;
    RWByteAddressBuffer meshlet_counts_buffer = ResourceDescriptorHeap[g_BinningParams.meshletCountsBufferIndex];

    if (meshletIndex >= GetMeshletsCount())
        return;

    uint bin = GetBin(meshletIndex);

    // WaveOps optimzed loop to write meshlet indices to its associated bins.
    bool finished = false;
    while (WaveActiveAnyTrue(!finished))
    {
        // Mask out all threads which are already finished
        if (!finished)
        {
            const uint firstBin = WaveReadLaneFirst(bin);
            if (firstBin == bin)
            {
                // Accumulate the meshlet count for all active threads
                uint originalValue;
                InterlockedAdd_WaveOps_ByteAddressBuffer(meshlet_counts_buffer, firstBin * sizeof(uint), 1, originalValue);
                finished = true;
            }
        }
    }
}