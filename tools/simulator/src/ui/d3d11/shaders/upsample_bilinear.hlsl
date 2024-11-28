
cbuffer constant_buffer_0 : register(b0)
{
    // out buffer is always 2x
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float2 _padding;
};

// StructuredBuffer<float> g_input_buffer : register(t0);
StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(32, 32, 1)]
void CSUpsampleBilinear(uint3 DTid : SV_DispatchThreadID) {
    // Skip edges
    const uint out_buffer_width = g_in_buffer_width * 2;
    if (DTid.x <= 1 ||
        DTid.x >= g_in_buffer_width - 2 ||
        DTid.y <= 1 ||
        DTid.y >= g_in_buffer_height - 2)
    {
        uint input_index = (DTid.x) + (DTid.y) * g_in_buffer_width;
        const float value = g_input_buffer[input_index];
        g_output_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 0) * out_buffer_width] = value;
        g_output_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 0) * out_buffer_width] = value;
        g_output_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 1) * out_buffer_width] = value;
        g_output_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 1) * out_buffer_width] = value;
        return;
    }

    const float TL = g_input_buffer[ (DTid.x + 0) + (DTid.y + 0) * g_in_buffer_width];
    const float TR = g_input_buffer[ (DTid.x + 1) + (DTid.y + 0) * g_in_buffer_width];
    const float BL = g_input_buffer[ (DTid.x + 0) + (DTid.y + 1) * g_in_buffer_width];
    const float BR = g_input_buffer[ (DTid.x + 1) + (DTid.y + 1) * g_in_buffer_width];
    // float values[4] = {
    //     g_input_buffer[ (DTid.x + 0) + (DTid.y + 0) * g_in_buffer_width], // tl
    //     g_input_buffer[ (DTid.x + 1) + (DTid.y + 0) * g_in_buffer_width], // tr
    //     g_input_buffer[ (DTid.x + 0) + (DTid.y + 1) * g_in_buffer_width], // bl
    //     g_input_buffer[ (DTid.x + 1) + (DTid.y + 1) * g_in_buffer_width], // br
    // };

    [unroll]
    for (uint y_out = 0; y_out < 2; y_out++)
    {
        [unroll]
        for (uint x_out = 0; x_out < 2; x_out++)
        {
            uint output_index = (DTid.x * 2 + x_out) + (DTid.y * 2 + y_out) * out_buffer_width;
            if (x_out == 0 && y_out == 0) {
                const float xT = lerp(TL, TR, 0.25);
                const float xB = lerp(BL, BR, 0.25);
                const float y = lerp(xT, xB, 0.25);
                g_output_buffer[output_index] = y;
            }
            else if (x_out == 1 && y_out == 0) {
                const float xT = lerp(TL, TR, 0.75);
                const float xB = lerp(BL, BR, 0.75);
                const float y = lerp(xT, xB, 0.25);
                g_output_buffer[output_index] = y;
            }
            else if (x_out == 0 && y_out == 1) {
                const float xT = lerp(TL, TR, 0.25);
                const float xB = lerp(BL, BR, 0.25);
                const float y = lerp(xT, xB, 0.75);
                g_output_buffer[output_index] = y;
            }
            else if (x_out == 1 && y_out == 1) {
                const float xT = lerp(TL, TR, 0.75);
                const float xB = lerp(BL, BR, 0.75);
                const float y = lerp(xT, xB, 0.75);
                g_output_buffer[output_index] = y;
            }
        }
    }
}

