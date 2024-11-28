
static const float s_gaussian_kernel_5[5][5] = {
    {  1,  4,  7,  4, 1 },
    {  4, 16, 26, 16, 4 },
    {  7, 26, 41, 26, 7 },
    {  4, 16, 26, 16, 4 },
    {  1,  4,  7,  4, 1 },
};

static const float s_kernel_sum_inv = 1.0f / 273.0f;

cbuffer constant_buffer_0 : register(b0)
{
    // out buffer is always 2x
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float2 _padding;
};

StructuredBuffer<float> g_input_buffer : register(t0);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(32, 32, 1)]
void CSUpsampleBlur(uint3 DTid : SV_DispatchThreadID) {
    // Skip edges
    const uint out_buffer_width = g_in_buffer_width * 2;
    if (DTid.x <= 1 ||
        DTid.x >= g_in_buffer_width - 2 ||
        DTid.y <= 1 ||
        DTid.y >= g_in_buffer_height - 2)
    {
        g_output_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 0) * out_buffer_width] = 0.0;
        g_output_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 0) * out_buffer_width] = 0.0;
        g_output_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 1) * out_buffer_width] = 0.0;
        g_output_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 1) * out_buffer_width] = 0.0;
        return;
    }

    float sum = 0;

    [unroll]
    for (uint y = 0; y < 5; y++)
    {
        [unroll]
        for (uint x = 0; x < 5; x++)
        {
            uint input_index = (DTid.x + x - 2) + (DTid.y + y - 2) * g_in_buffer_width;
            sum += s_gaussian_kernel_5[y][x] * g_input_buffer[input_index];
        }
    }

    sum *= s_kernel_sum_inv;

    g_output_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 0) * out_buffer_width] = sum;
    g_output_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 0) * out_buffer_width] = sum;
    g_output_buffer[(DTid.x * 2 + 1) + (DTid.y * 2 + 1) * out_buffer_width] = sum;
    g_output_buffer[(DTid.x * 2 + 0) + (DTid.y * 2 + 1) * out_buffer_width] = sum;
}
