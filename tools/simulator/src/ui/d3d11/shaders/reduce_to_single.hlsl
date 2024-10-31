#include "parallel_reduction_common.hlsli"

cbuffer constant_buffer_0 : register(b0)
{
    uint g_element_count;
    uint g_thread_group_count_x;
};

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

#define GROUP_THREADS 128
groupshared float g_shader_mem[GROUP_THREADS];

[numthreads(GROUP_THREADS, 1, 1)]
void CSReduceToSingle(uint3 Gid : SV_GroupID, uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex)
{
    if (DTid.x < g_thread_group_count_x)
    {
        g_shader_mem[GI] = g_input_buffer[DTid.x];
    }
    else
    {
        g_shader_mem[GI] = 0;
    }

    GroupMemoryBarrierWithGroupSync();
    if (GI < 64)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 64);

    GroupMemoryBarrierWithGroupSync();
    if (GI < 32)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 32);

    GroupMemoryBarrierWithGroupSync();
    if (GI < 16)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 16);

    GroupMemoryBarrierWithGroupSync();
    if (GI < 8)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 8);

    GroupMemoryBarrierWithGroupSync();
    if (GI < 4)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 4);

    GroupMemoryBarrierWithGroupSync();
    if (GI < 2)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 2);

    GroupMemoryBarrierWithGroupSync();
    if (GI < 1)
        g_shader_mem[GI] = PARALLEL_REDUCTION_OPERATOR(g_shader_mem, GI, GI + 1);

    if (GI == 0)
    {
        g_output_buffer[Gid.x] = g_shader_mem[0];
    }
}