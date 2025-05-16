cbuffer RemapData : register(b0)
{
    uint g_buffer_width;
    uint g_buffer_height;
    uint g_curve_keys_count;
    uint _padding;
}

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);
StructuredBuffer<float2> g_curve : register(t1);

// NOTE: This only supports linear curves and assumes g_curve_keys_count >= 2
float EvaluateCurve(float input)
{
    // Out of range
    if (input < g_curve[0].x)
    {
        return g_curve[0].y;
    }

    for (uint i = 0; i < g_curve_keys_count - 1; i++)
    {
        if (input >= g_curve[i].x && input < g_curve[i + 1].x)
        {
            return lerp(g_curve[i].y, g_curve[i + 1].y, (input - g_curve[i].x) / (g_curve[i + 1].x - g_curve[i].x));
        }
    }

    // Out of range
    return g_curve[g_curve_keys_count - 1].y;
}

[numthreads(8, 8, 1)] void CSRemapCurve(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
    if (dispatch_thread_id.x < g_buffer_width && dispatch_thread_id.y < g_buffer_height)
    {
        uint index = dispatch_thread_id.x + dispatch_thread_id.y * g_buffer_width;
        g_output_buffer[index] = EvaluateCurve(g_input_buffer[index]);
    }
}