cbuffer constant_buffer_0 : register(b0)
{
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float g_sediment_capacity_factor;
    float g_droplet_max_sediment;
    float g_deposit_speed;
    float g_erosion_speed;
    float g_evaporation;
    float g_momentum;
};

StructuredBuffer<float> g_input_buffer_heightmap : register(t0);
RWStructuredBuffer<float> g_output_buffer_heightmap : register(u0);
RWStructuredBuffer<float2> g_output_buffer_droplet_positions : register(u1); 
RWStructuredBuffer<float> g_output_buffer_droplet_energies : register(u2); 
RWStructuredBuffer<float> g_output_buffer_droplet_sizes : register(u3); 
RWStructuredBuffer<float> g_output_buffer_droplet_sediment : register(u4); 
RWStructuredBuffer<float> g_output_buffer_inflow : register(u5); 
RWStructuredBuffer<float2> g_output_buffer_droplet_positions_new : register(u6); 

float height_at_pos(uint x, uint y, float2 droplet_pos) {
    const uint index_bl = x + 0 + (y + 0) * g_in_buffer_width;
    const uint index_br = x + 1 + (y + 0) * g_in_buffer_width;
    const uint index_tl = x + 0 + (y + 1) * g_in_buffer_width;
    const uint index_tr = x + 1 + (y + 1) * g_in_buffer_width;
    const float height_bl = g_output_buffer_heightmap[index_bl];
    const float height_br = g_output_buffer_heightmap[index_br];
    const float height_tl = g_output_buffer_heightmap[index_tl];
    const float height_tr = g_output_buffer_heightmap[index_tr];
    const float height_bot = lerp(height_bl, height_br, droplet_pos.x);
    const float height_top = lerp(height_tl, height_tr, droplet_pos.x);
    const float height = lerp(height_bot, height_top, droplet_pos.y);
    return height;
}

float2 height_gradient_at_pos(uint x, uint y, float2 droplet_pos, out float height) {
    const uint index_bl = x + 0 + (y + 0) * g_in_buffer_width;
    const uint index_br = x + 1 + (y + 0) * g_in_buffer_width;
    const uint index_tl = x + 0 + (y + 1) * g_in_buffer_width;
    const uint index_tr = x + 1 + (y + 1) * g_in_buffer_width;
    const float height_bl = g_output_buffer_heightmap[index_bl];
    const float height_br = g_output_buffer_heightmap[index_br];
    const float height_tl = g_output_buffer_heightmap[index_tl];
    const float height_tr = g_output_buffer_heightmap[index_tr];
    const float height_bot = lerp(height_bl, height_br, droplet_pos.x);
    const float height_top = lerp(height_tl, height_tr, droplet_pos.x);
    height = lerp(height_bot, height_top, droplet_pos.y);
    
    const float dx_bot = height_bl - height_br; // -50
    const float dx_top = height_tl - height_tr; // 0
    const float dx = lerp(dx_bot, dx_top, droplet_pos.y); // -45
    const float dy_left = height_bl - height_tl; // -100
    const float dy_right = height_br - height_tr; // 50
    const float dy = lerp(dy_left, dy_right, droplet_pos.x); // -100 -> 50 @ 80% = 20

    return float2(dx, dy);
}

float length_squared(float2 vec) {
    return vec.x * vec.x + vec.y * vec.y;
}

[numthreads(32, 32, 1)] void CSErosion_2_collect_flow(uint3 DTid : SV_DispatchThreadID)
{
    // Skip edges
    const uint range = 2;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2)
    {
        const uint index_in = DTid.x + DTid.y * g_in_buffer_width;
        // g_output_buffer_heightmap[index_in] = 1000;
        return;
    }
    
    // TODO: Distinguise between sediment and erosion
    // TODO: Momentum

    const uint index_in = DTid.x + DTid.y * g_in_buffer_width;
    float total_inflow = 0;
    float max_inflow = 100000;
    
    const uint inflow_base_index = DTid.x * 8 + DTid.y * 8 * g_in_buffer_width;
    const uint inflow_offset_index = 0;
    for (uint yy = 0; yy <= 2; yy++) {
        for (uint xx = 0; xx <= 2; xx++) {
            const uint x = DTid.x + xx - 1;
            const uint y = DTid.y + yy - 1;
    // for (uint y = DTid.y - 1; y <= DTid.y + 1; y++) {
    //     for (uint x = DTid.x - 1; x <= DTid.x + 1; x++) {
            if (x == DTid.x && y == DTid.y) {
                // CORRECT?!
                // Probably not
                // remember 8 -> 9
                continue;
            }

            const uint inflow_index = inflow_base_index + inflow_offset_index;
            g_output_buffer_inflow[inflow_index] = 0;
            inflow_offset_index += 1;

            const uint droplet_index = x + y * g_in_buffer_width;
            const float size = g_output_buffer_droplet_sizes[droplet_index];
            if (size == 0) {
                continue;
            }

            const float2 droplet_pos = g_output_buffer_droplet_positions[droplet_index];

            float droplet_height = 0;
            const float2 gradient = height_gradient_at_pos(x, y, droplet_pos, droplet_height);
            if (length_squared(gradient) < 0.001) {
                continue; 
            }

            const float2 gradient_01 = normalize(gradient);
            const float2 cell_pos = float2(x, y);
            const float2 target_pos = cell_pos + droplet_pos + gradient_01;
            const uint target_x = uint(floor(target_pos.x));
            const uint target_y = uint(floor(target_pos.y));
            if (target_x == DTid.x && target_y == DTid.y) {
                // g_output_buffer_heightmap[index_in] = 1000;

                // store new pos in world space
                g_output_buffer_droplet_positions_new[droplet_index] = target_pos;

                const float2 droplet_pos_new = float2(target_pos.x - DTid.x, target_pos.y - DTid.y);
                const float target_height = height_at_pos(DTid.x, DTid.y, droplet_pos_new);
                const float height_difference = target_height - droplet_height; 
                const bool flowing_downhill = height_difference < 0;

                const float current_carrying = g_output_buffer_droplet_sediment[droplet_index];
                const float max_terrain_shift = abs(height_difference * 0.5); // 0.5 not strictly necessary?

                const float energy = g_output_buffer_droplet_energies[droplet_index];
                const float sediment_carrying_capacity = -height_difference * size * energy * g_sediment_capacity_factor;

                if (current_carrying < sediment_carrying_capacity && flowing_downhill) {
                    // Inflow
                    // Droplet can pick up more sediment from the neighboring cell
                    const float remaining_sediment_capacity_in_droplet = g_droplet_max_sediment - current_carrying;
                    const float to_pick_up_optimal = g_erosion_speed * (sediment_carrying_capacity - current_carrying);
                    float to_pick_up = min(remaining_sediment_capacity_in_droplet, to_pick_up_optimal);
                    
                    // Don't flip heights
                    to_pick_up = min(to_pick_up, max_terrain_shift);
                    
                    // Need to ensure TOTAL inflow will not flip heights
                    max_inflow = min(max_inflow, max_terrain_shift);
                    total_inflow += to_pick_up;
                    
                    // May get reduced later by total inflow
                    g_output_buffer_inflow[inflow_index] = to_pick_up;
                }
                else {
                    // Full, drop some at the neighboring cell
                    float to_drop = min(current_carrying, current_carrying - sediment_carrying_capacity);
                    
                    // Don't flip heights
                    to_drop = min(to_drop, max_terrain_shift);

                    // Gotta be negative
                    to_drop = -to_drop;

                    // Will not be reduced
                    g_output_buffer_inflow[inflow_index] = to_drop;
                }
            }
        }
    }

    if (total_inflow > 0) {
        const float carry_divisor = max_inflow * rcp(total_inflow);
        for (uint i_flow = 0; i_flow < 8; i_flow++) {
            const float inflow = g_output_buffer_inflow[inflow_base_index + index_in];
            if (inflow > 0) {
                g_output_buffer_inflow[inflow_base_index + index_in] *= carry_divisor;
            }
        }
    }
}
