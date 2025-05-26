cbuffer constant_buffer_0 : register(b0)
{
    uint g_buffer_width;
    uint g_buffer_height;
    float g_world_width;
    float g_world_height;
    float g_threshold;
};

StructuredBuffer<float> g_input : register(t0);
RWStructuredBuffer<float2> g_points : register(u0);
RWStructuredBuffer<uint> g_counter : register(u1);

[numthreads(32, 32, 1)] void CSGatherPoints(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x < g_buffer_width && DTid.y < g_buffer_height)
    {
        uint index = DTid.x + DTid.y * g_buffer_width;
        float value = g_input[index];
        if (value >= g_threshold)
        {
            float2 worldPosition = float2(
                (DTid.x / float(g_buffer_width)) * g_world_width, 
                (DTid.y / float(g_buffer_height)) * g_world_height
            );

            uint pointIndex;
            InterlockedAdd(g_counter[0], 1, pointIndex);

            g_points[pointIndex] = worldPosition;
        }
    }
}
