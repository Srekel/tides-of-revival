#include "parallel_reduction_common.hlsli"

cbuffer constant_buffer_0 : register(b0)
{
    uint g_thread_group_count_x;
    uint g_thread_group_count_y;
};

cbuffer constant_buffer_1 : register(b1)
{
    uint g_buffer_width;
    uint g_buffer_height;
};

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

#define BLOCK_SIZE 8

#define GROUP_THREADS (BLOCK_SIZE * BLOCK_SIZE)
groupshared float g_shader_mem[GROUP_THREADS];

float FullPixelReduction(uint3 DTid)
{
    float result = 0.0f;
    float value = 0.0f;

    uint x = 0;
    uint y = 0;
    uint index = 0;

    x = DTid.x;
    y = DTid.y;
    value = g_input_buffer[x + y * g_buffer_width];
    result = value;

    x = DTid.x + BLOCK_SIZE * g_buffer_width;
    y = DTid.y + 0;
    value = g_input_buffer[x + y * g_buffer_width];
    result = SERIAL_OPERATOR(result, value);

    x = DTid.x + 0;
    y = DTid.y + BLOCK_SIZE * g_buffer_height;
    value = g_input_buffer[x + y * g_buffer_width];
    result = SERIAL_OPERATOR(result, value);

    x = DTid.x + BLOCK_SIZE * g_buffer_width;
    y = DTid.y + BLOCK_SIZE * g_buffer_height;
    value = g_input_buffer[x + y * g_buffer_width];
    result = SERIAL_OPERATOR(result, value);

    return result;
}

[numthreads(BLOCK_SIZE, BLOCK_SIZE, 1)]
void CSReduceTo1D(uint3 Gid : SV_GroupID, uint3 DTid : SV_DispatchThreadID, uint3 GTid : SV_GroupThreadID, uint GI : SV_GroupIndex)
{
    g_shader_mem[GI] = FullPixelReduction(DTid);

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
        g_output_buffer[Gid.y * g_buffer_width + Gid.x] = g_shader_mem[0];
    }
}