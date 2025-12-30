cbuffer SubtractData : register(b0)
{
    uint g_buffer_width;
    uint g_buffer_height;
    float2 _padding;
}

StructuredBuffer<float> g_input_buffer0 : register(t0);
StructuredBuffer<float> g_input_buffer1 : register(t1);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(8, 8, 1)]
void CSSubtract(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
    if (dispatch_thread_id.x < g_buffer_width && dispatch_thread_id.y < g_buffer_height)
    {
        uint index = dispatch_thread_id.x + dispatch_thread_id.y * g_buffer_width;
        float value0 = g_input_buffer0[index];
        float value1 = g_input_buffer1[index];
        g_output_buffer[index] = value0 - value1;
    }
}
