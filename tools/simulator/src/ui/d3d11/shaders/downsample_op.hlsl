
#define COMPUTE_OPERATOR_MIN 1
#define COMPUTE_OPERATOR_MAX 2
#define COMPUTE_OPERATOR_AVERAGE 3
#define COMPUTE_OPERATOR_SUM 6

cbuffer constant_buffer_0 : register(b0)
{
    uint g_out_buffer_width;
    uint g_out_buffer_height;
    uint g_operator;
    float _padding;
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

    if (g_operator == COMPUTE_OPERATOR_MIN)
    {
        output_value = min(min(TL, TR), min(BL, BR));
    }
    else if (g_operator == COMPUTE_OPERATOR_MAX)
    {
        output_value = max(max(TL, TR), max(BL, BR));
    }
    else if (g_operator == COMPUTE_OPERATOR_AVERAGE)
    {
        output_value = (TL + TR + BL + BR) * 0.25;
    }
    else if (g_operator == COMPUTE_OPERATOR_SUM)
    {
        output_value = TL + TR + BL + BR;
    }
    else {
        output_value = DTid.x % 2;
    }

    uint output_index = DTid.x + DTid.y * g_out_buffer_width;
    g_output_buffer[DTid.x] = output_value;
}