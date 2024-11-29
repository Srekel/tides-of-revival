cbuffer constant_buffer_0 : register(b0)
{
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float g_gradient_max;
    float _padding;
};

StructuredBuffer<float> g_input_buffer_gradient : register(t0);
StructuredBuffer<float> g_input_buffer_height : register(t1);
RWStructuredBuffer<float> g_output_buffer : register(u0);
RWStructuredBuffer<float> g_output_buffer_gradient : register(u1); 
// RWStructuredBuffer<float2> g_output_buffer_score : register(u2); 

[numthreads(32, 32, 1)] void CSTerrace(uint3 DTid : SV_DispatchThreadID)
{
    const uint step_dist = 1;
    const uint steps = 15;
    const uint steps_half = floor(steps / 2); // 7
    const uint range = step_dist * steps;     // 15

    const uint index_in = DTid.x + DTid.y * g_in_buffer_width;
    g_output_buffer_gradient[index_in] = g_input_buffer_gradient[index_in];

    // Skip edges
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2)
    {
        g_output_buffer[index_in] = g_input_buffer_height[index_in];
        return;
    }

    float curr_gradient = sat(2*30*g_input_buffer_gradient[index_in]);
    float curr_height = g_input_buffer_height[index_in];

    uint index_best = 0;
    float best_score_dist = 0;
    float best_score_gradient = 0;
    // float total_score = 0;
    // float total_height = 0;

     for (uint y = 0; y < steps; y++)
    {
         for (uint x = 0; x < steps; x++)
        {
            if (x == steps_half && y == steps_half)
            {
                continue;
            }

            uint index_x = DTid.x + x * step_dist - steps_half * step_dist;
            uint index_y = DTid.y + y * step_dist - steps_half * step_dist;
            uint index_sample = index_x + index_y * g_in_buffer_width;
            float height_sample = g_input_buffer_height[index_sample];
            if (height_sample < curr_height)  {
                continue;
            }


            float gradient = 30 * g_input_buffer_gradient[index_sample];
            float dist_x = ((float)x - (float)steps_half);
            float dist_y = ((float)y - (float)steps_half);
            // float distance = range; // sqrt(dist_x * dist_x + dist_y * dist_y);
            float distance = sqrt(dist_x * dist_x + dist_y * dist_y);
            // float distance = dist_x * dist_x + dist_y * dist_y;
            // float distance = 1;
            float distance_score = clamp(1 - distance / (float)range, 0, 1);
            float gradient_score = clamp(1 - gradient * gradient, 0, 1);
            float score = gradient_score * distance_score;
            // total_score += score;

            // float best_height = g_input_buffer_height[index_sample];
            // float new_height = lerp(curr_height, best_height, best_score_dist);
            // total_height += best_height * score;

            if (score > best_score_dist)
            {
                best_score_gradient = gradient_score;
                best_score_dist = score;
                index_best = index_sample;
                // g_output_buffer_score[index_in].x = index_x;
                // g_output_buffer_score[index_in].y = index_y;
            }
        }
    }

    float best_height = g_input_buffer_height[index_best];
    if (abs(best_height- curr_height) < 0.01) {
        g_output_buffer[index_in] = curr_height;
    }
    else {
        // float new_height = lerp(curr_height, best_height, best_score_dist * curr_gradient);
        // g_output_buffer[index_in] = new_height;
        g_output_buffer[index_in] = curr_height;
    }
}
