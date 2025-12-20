cbuffer constant_buffer_0 : register(b0)
{
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float g_sediment_capacity;
    float _padding1;
};


StructuredBuffer<float> g_input_buffer_heightmap : register(t0);
RWStructuredBuffer<float> g_output_buffer_heightmap : register(u0);
RWStructuredBuffer<float2> g_output_buffer_droplet_positions : register(u1); 
RWStructuredBuffer<float> g_output_buffer_droplet_energies : register(u2); 
RWStructuredBuffer<float> g_output_buffer_droplet_sizes : register(u3); 
RWStructuredBuffer<float> g_output_buffer_droplet_sediment : register(u4); 
RWStructuredBuffer<float> g_output_buffer_inflow : register(u5); 
RWStructuredBuffer<float> g_output_buffer_outflow : register(u6); 

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

// struct HeightANdGradient {}

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
    const float dy_left = height_bl - height_tl; // 0
    const float dy_right = height_br - height_tr; // 50
    const float dy = lerp(dy_left, dy_right, droplet_pos.x); // 40

    return float2(dx, dy);
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
        return;
    }
    
    // TODO: Distinguise between sediment and erosion

    const uint index_in = DTid.x + DTid.y * g_in_buffer_width;
    float total_inflow = 0;
    float max_carry = 100000;
    const uint inflow_base_index = DTid.x * 8 + DTid.y * 8 * g_in_buffer_width;
    const uint inflow_offset_index = 0;
    for (uint y = DTid.y - 1; y <= DTid.y + 1; y++) {
        for (uint x = DTid.x - 1; x <= DTid.x + 1; x++) {
            if (x == DTid.x && y == DTid.y) {
                // CORRECT?!
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

            const float droplet_pos = g_output_buffer_droplet_positions[droplet_index];

            float height = 0;
            const float2 gradient = height_gradient_at_pos(x, y, droplet_pos, height);

            const float2 gradient_01 = normalize(gradient);
            const float2 cell_pos = float2(x, y);
            const float2 target_pos = cell_pos + droplet_pos + gradient_01;
            if ((uint)target_pos.x == DTid.x && (uint)target_pos.y == DTid.y) {
                const float target_height = height_at_pos(DTid.x, DTid.y, float2(target_pos.x - DTid.x, target_pos.y - DTid.y));
                const float height_difference = length(gradient);
                const float energy = g_output_buffer_droplet_energies[droplet_index];
                const float how_much_to_carry_in_droplet = height_difference * size * energy * g_sediment_capacity;
                const float current_carrying = g_output_buffer_droplet_sediment[droplet_index];
                const float remaining_possible_sediment_capacity_in_droplet = max(0, 15 - current_carrying);
                const float max_carry_limit = (height - target_height) * 0.5; // don't flip heights
                const float to_carry = min(min(remaining_possible_sediment_capacity_in_droplet, how_much_to_carry_in_droplet), max_carry_limit);

                max_carry = min(max_carry, to_carry);
                total_inflow += to_carry;
                g_output_buffer_inflow[inflow_index] = to_carry;
            }
        }
    }

    if (total_inflow > 0) {
        const float carry_divisor = max_carry * rcp(total_inflow);
        for (uint i_flow = 0; i_flow < 8; i_flow++) {
            g_output_buffer_inflow[inflow_base_index + index_in] *= carry_divisor;
        }
    }

    
    // const uint inflow_index = inflow_base_index + inflow_offset_index;
    // g_output_buffer_inflow[inflow_index] = 0;
    // inflow_offset_index += 1;

    // const uint droplet_index = x + y * g_in_buffer_width;
    // const float size = g_output_buffer_droplet_sizes[droplet_index];
    // if (size == 0) {
    //     continue;
    // }

    // const float droplet_pos = g_output_buffer_droplet_positions[droplet_index];

    // float height = 0;
    // const float2 gradient = height_gradient_at_pos(x, y, droplet_pos, height);

    // const float2 gradient_01 = normalize(gradient);
    // const float2 cell_pos = float2(x, y);
    // const float2 target_pos = cell_pos + droplet_pos + gradient_01;
    // if ((uint)target_pos.x == DTid.x && (uint)target_pos.y == DTid.y) {
    //     const float target_height = height_at_pos(DTid.x, DTid.y, float2(target_pos.x - DTid.x, target_pos.y - DTid.y));
    //     const float height_difference = length(gradient);
    //     const float energy = g_output_buffer_droplet_energies[droplet_index];
    //     const float how_much_to_carry_in_droplet = height_difference * size * energy * g_sediment_capacity;
    //     const float current_carrying = g_output_buffer_droplet_sediment[droplet_index];
    //     const float remaining_possible_sediment_capacity_in_droplet = max(0, 15 - current_carrying);
    //     const float max_carry_limit = (height - target_height) * 0.5; // don't flip heights
    //     const float to_carry = min(min(remaining_possible_sediment_capacity_in_droplet, how_much_to_carry_in_droplet), max_carry_limit);

    //     max_carry = min(max_carry, to_carry);
    //     total_inflow += to_carry;
    //     g_output_buffer_inflow[inflow_index] = to_carry;
    // }
}
