const float s_sobel_filter_x[3][3] = {
    { -1.0,  0.0,  1.0 },
    { -2.0,  0.0,  2.0 },
    { -1.0,  0.0,  1.0 },
};

const float s_sobel_filter_y[3][3] = {
    { -1.0, -0.0, -1.0 },
    {  0.0,  0.0,  0.0 },
    {  1.0,  2.0,  1.0 },
};

cbuffer constant_buffer_0 : register(b0)
{
    uint g_buffer_width;
    uint g_buffer_height;
    float g_height_ratio;
}

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(8, 8, 1)]
void CSGradient(uint3 dispatch_thread_id : SV_DispatchThreadID)
{
    // Skip edges
    if (dispatch_thread_id.x == 0 ||
        dispatch_thread_id.x == g_buffer_width - 1 ||
        dispatch_thread_id.y == 0 ||
        dispatch_thread_id.y == g_buffer_height - 1)
    {
        return;
    }

    // This check is necessary because some threads could be outside the bounds of the buffer
    if (dispatch_thread_id.x < g_buffer_width && dispatch_thread_id.y < g_buffer_height)
    {
        float2 sum = 0;

        [unroll]
        for (uint x = 0; x < 3; x++)
        {
            [unroll]
            for (uint y = 0; y < 3; y++)
            {
                // NOTE: I'm assuming input and output buffers are the same size
                uint input_index = (dispatch_thread_id.x + x - 1) + (dispatch_thread_id.y + y - 1) * g_buffer_width;
                sum.x = s_sobel_filter_x[x][y] * g_input_buffer[input_index] * g_height_ratio;
                sum.y = s_sobel_filter_y[x][y] * g_input_buffer[input_index] * g_height_ratio;
            }
        }

        // dot(v, v) = v.x * v.x + v.y * v.y
        float gradient_value = sqrt(dot(sum, sum));
        uint index = dispatch_thread_id.x + dispatch_thread_id.y * g_buffer_width;
        g_output_buffer[index] = gradient_value;
    }
}