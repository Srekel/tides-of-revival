cbuffer constant_buffer_0 : register(b0)
{
    uint g_out_buffer_width;
    uint g_out_buffer_height;
    uint g_operator; // 0: min, 1: max, 2: avg, 3: sum
};

StructuredBuffer<float> g_input_buffer : register(t0); // Input buffer is 2x output buffer
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(32, 32, 1)] void CSDownsampleOp(uint3 DTid : SV_DispatchThreadID)
{
    const float TL = g_input_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 0) * g_out_buffer_width];
    const float TR = g_input_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 0) * g_out_buffer_width];
    const float BL = g_input_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 1) * g_out_buffer_width];
    const float BR = g_input_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 1) * g_out_buffer_width];

    float output_value = 0.0;

    if (g_operator == 0) // min
    {
        output_value = min(min(TL, TR), min(BL, BR));
    }
    else if (g_operator == 1) // max
    {
        output_value = max(max(TL, TR), max(BL, BR));
    }
    else if (g_operator == 2) // avg
    {
        output_value = (TL + TR + BL + BR) * 0.5;
    }
    else if (g_operator == 3) // sum
    {
        output_value = TL + TR + BL + BR;
    }

    uint output_index = DTid.x + DTid.y * g_out_buffer_width;
    g_output_buffer[DTid.x] = output_value;
}