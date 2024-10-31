cbuffer RemapData : register(b0)
{
    float2 g_from;
    float2 g_to;
    uint g_buffer_width;
    uint g_buffer_height;
    float2 _padding;
}

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

float Remap(float value, float2 from, float2 to)
{
    return to.x + (value - from.x) * (to.y - to.x) / (from.y - from.x);
}

[numthreads(8, 8, 1)]
void CSRemap(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
    if (dispatch_thread_id.x < g_buffer_width && dispatch_thread_id.y < g_buffer_height)
    {
        uint index = dispatch_thread_id.x + dispatch_thread_id.y * g_buffer_width;
        g_output_buffer[index] = Remap(g_input_buffer[index], g_from, g_to);
    }
}