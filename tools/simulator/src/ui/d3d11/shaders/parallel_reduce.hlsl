StructuredBuffer<float> g_input_data : register(t0);
RWStructuredBuffer<float> g_output_data : register(u0);

#ifndef GROUP_DIMENSION_X
#define GROUP_DIMENSION_X 512
#endif

#define REDUCE_OPERATOR_MIN 1
#define REDUCE_OPERATOR_MAX 2

groupshared float g_shared_mem[GROUP_DIMENSION_X];

cbuffer cb0 : register(b0)
{
    float g_first_pass;
    uint g_buffer_width;
    uint g_buffer_height;
    uint g_operator;
};

[numthreads(GROUP_DIMENSION_X, 1, 1)]
void CSReduceSum(uint3 DTid : SV_DispatchThreadID, uint3 Gid : SV_GroupID, uint GI : SV_GroupIndex)
{
    const uint tid = DTid.x;
    const uint gid = Gid.x;
    const uint index = GI;

    if (g_first_pass)
    {
        uint2 p_id_0 = uint2((tid * 2 + 0) % g_buffer_width, (tid * 2 + 0) / g_buffer_height);
        uint2 p_id_1 = uint2((tid * 2 + 1) % g_buffer_width, (tid * 2 + 1) / g_buffer_height);
        float a = g_input_data[p_id_0.x + p_id_0.y * g_buffer_width];
        float b = g_input_data[p_id_1.x + p_id_1.y * g_buffer_width];
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(a, b);
        else
            g_shared_mem[index] = max(a, b);
    }
    else
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_output_data[tid * 2], g_output_data[tid * 2 + 1]);
        else
            g_shared_mem[index] = max(g_output_data[tid * 2], g_output_data[tid * 2 + 1]);
    }
    GroupMemoryBarrierWithGroupSync();

#if GROUP_DIMENSION_X > 256
    if (index < 256)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 256]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 256]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 128
    if (index < 128)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 128]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 128]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 64
    if (index < 64)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 64]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 64]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 32
    if (index < 32)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 32]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 32]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 16
    if (index < 16)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 16]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 16]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 8
    if (index < 8)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 8]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 8]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 4
    if (index < 4)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 4]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 4]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 2
    if (index < 2)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 2]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 2]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

#if GROUP_DIMENSION_X > 1
    if (index < 1)
    {
        if (g_operator == REDUCE_OPERATOR_MIN)
            g_shared_mem[index] = min(g_shared_mem[index], g_shared_mem[index + 1]);
        else
            g_shared_mem[index] = max(g_shared_mem[index], g_shared_mem[index + 1]);
    }
    GroupMemoryBarrierWithGroupSync();
#endif

    if (index == 0)
    {
        g_output_data[gid] = g_shared_mem[0];
    }
}