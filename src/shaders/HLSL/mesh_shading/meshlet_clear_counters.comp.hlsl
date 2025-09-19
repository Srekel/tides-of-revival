#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "types.hlsli"

struct ClearUAVParams
{
    uint candidateMeshletsCounterBufferIndex;
    uint visibleMeshletsCountersBufferIndex;
};

cbuffer g_ClearUAVParams : register(b0, UPDATE_FREQ_PER_FRAME)
{
    ClearUAVParams g_ClearUAVParams;
};

[numthreads(1, 1, 1)]
void main()
{
    RWByteAddressBuffer candidateMeshletsCountersBuffer = ResourceDescriptorHeap[g_ClearUAVParams.candidateMeshletsCounterBufferIndex];
    candidateMeshletsCountersBuffer.Store<uint>(COUNTER_TOTAL_CANDIDATE_MESHLETS * sizeof(uint), 0);
    candidateMeshletsCountersBuffer.Store<uint>(COUNTER_PHASE1_CANDIDATE_MESHLETS * sizeof(uint), 0);
    candidateMeshletsCountersBuffer.Store<uint>(COUNTER_PHASE2_CANDIDATE_MESHLETS * sizeof(uint), 0);

    RWByteAddressBuffer visibleMeshletsCountersBuffer = ResourceDescriptorHeap[g_ClearUAVParams.visibleMeshletsCountersBufferIndex];
    visibleMeshletsCountersBuffer.Store<uint>(COUNTER_PHASE1_VISIBLE_MESHLETS * sizeof(uint), 0);
    visibleMeshletsCountersBuffer.Store<uint>(COUNTER_PHASE2_VISIBLE_MESHLETS * sizeof(uint), 0);
}