cbuffer constant_buffer_0 : register(b0)
{
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float2 _padding;
};

StructuredBuffer<float> g_input_buffer_gradient : register(t0);
StructuredBuffer<float> g_input_buffer_height : register(t1);
RWStructuredBuffer<float> g_output_buffer : register(u0);

[numthreads(32, 32, 1)] void CSTerrace(uint3 DTid : SV_DispatchThreadID)
{
    const uint step_dist = 5;
    const uint steps = 3;
    const uint steps_half = floor(steps / 2) + 1;
    const uint range = step_dist * steps;

    // Skip edges
    if (DTid.x <= range ||
        DTid.x >= g_in_buffer_width - range - 1 ||
        DTid.y <= range ||
        DTid.y >= g_in_buffer_height - range - 1)
    {
        const uint index = DTid.x + DTid.y * g_in_buffer_width;
        g_output_buffer[index] = g_input_buffer_height[index];
        return;
    }

    uint best_index = 0;
    float best_score = 0;

    [unroll] for (uint y = 0; y < steps; y++)
    {
        [unroll] for (uint x = 0; x < steps; x++)
        {
            if (x == 0 && y == 0)
            {
                continue;
            }

            uint index_x = DTid.x + x * step_dist - steps_half * step_dist;
            uint index_y = DTid.y + y * step_dist - steps_half * step_dist;
            uint index = index_x + index_y * g_in_buffer_width;
            float gradient = g_input_buffer_gradient[index];
            float dist_x = ((float)x - steps_half) * step_dist;
            float dist_y = ((float)y - steps_half) * step_dist;
            float distance = sqrt(dist_x * dist_x + dist_y * dist_y);
            float distance_score = clamp(1 - distance / range, 0, 1);
            float gradient_score = clamp(1 - gradient, 0, 1);
            float score = gradient_score * distance_score;
            if (score > best_score)
            {
                best_score = score;
                best_index = index;
            }
        }
    }

    uint curr_index = DTid.x + DTid.y * g_in_buffer_width;
    float curr_height = g_input_buffer_height[curr_index];
    float best_height = g_input_buffer_height[best_index];
    float new_height = lerp(curr_height, best_height, best_score);
    g_output_buffer[curr_index] = new_height;
}
