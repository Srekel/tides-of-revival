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

struct Droplet
{
    float size;
    float energy;
    float sediment;
    float _padding4;
    float2 position;
    float _padding7;
    float _padding8;
};

StructuredBuffer<float> g_input_buffer_heightmap : register(t0);
RWStructuredBuffer<float> g_output_buffer_heightmap : register(u0);
RWStructuredBuffer<Droplet> g_output_buffer_droplets : register(u1);
RWStructuredBuffer<Droplet> g_output_buffer_droplets_next : register(u2);
RWStructuredBuffer<float> g_output_buffer_inflow : register(u3);
RWStructuredBuffer<float> g_output_buffer_debug : register(u4);

float height_at_pos(uint x, uint y, float2 droplet_pos)
{
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

float2 height_gradient_at_pos(uint x, uint y, float2 droplet_pos, out float height)
{
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

    const float dx_bot = height_bl - height_br;              // -50
    const float dx_top = height_tl - height_tr;              // 0
    const float dx = lerp(dx_bot, dx_top, droplet_pos.y);    // -45
    const float dy_left = height_bl - height_tl;             // -100
    const float dy_right = height_br - height_tr;            // 50
    const float dy = lerp(dy_left, dy_right, droplet_pos.x); // -100 -> 50 @ 80% = 20

    return float2(dx, dy);
}

float length_squared(float2 vec)
{
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
        const uint index_self = DTid.x + DTid.y * g_in_buffer_width;
        // g_output_buffer_heightmap[index_self] = 1000;
        return;
    }

    // TODO: Distinguise between sediment and erosion
    // TODO: Momentum

    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    const Droplet curr_droplet = g_output_buffer_droplets[index_self];
    Droplet next_droplet = g_output_buffer_droplets_next[index_self];

    const float curr_size = curr_droplet.size;
    if (curr_size == 0)
    {
        // g_output_buffer_debug[index_self] = 10;
        return;
    }

    float curr_droplet_height = 0;
    float next_droplet_height = 0;
    const float2 curr_gradient = height_gradient_at_pos(DTid.x, DTid.y, curr_droplet.position, curr_droplet_height);
    if (length_squared(curr_gradient) < 0.001)
    {
        g_output_buffer_debug[index_self] = 20;
        return;
    }

    const float2 curr_gradient_01 = normalize(curr_gradient);
    const float2 curr_cell_pos = float2(DTid.x, DTid.y);
    const float2 next_pos_world = curr_cell_pos + curr_droplet.position + curr_gradient_01;
    const uint next_pos_world_x = uint(floor(next_pos_world.x));
    const uint next_pos_world_y = uint(floor(next_pos_world.y));

    // next_droplet.position = float2(next_pos_world.x - next_pos_world_x, next_pos_world.y - next_pos_world_y);
    const float2 next_gradient = height_gradient_at_pos(next_pos_world_x, next_pos_world_y, next_droplet.position, next_droplet_height);
    const float height_diff = next_droplet_height - curr_droplet_height;
    const bool flowing_downhill = height_diff < 0;

    const float curr_sediment = curr_droplet.sediment;
    const float max_terrain_shift = abs(height_diff * 0.5);

    const float curr_energy = curr_droplet.energy;
    const float sediment_carrying_capacity = flowing_downhill ? -height_diff * curr_size * curr_energy * g_sediment_capacity_factor : 0;

    if (!flowing_downhill)
    {
        next_droplet.position = float2(DTid.x + curr_droplet.position.x, DTid.y + curr_droplet.position.y);
        next_droplet.sediment = curr_sediment * 0.9; // Drop some amount
        next_droplet.energy = 0;
        next_droplet.size = curr_droplet.size * g_evaporation;
        g_output_buffer_debug[index_self] = 150;
    }
    else if (curr_sediment < sediment_carrying_capacity)
    {
        // Flowing down, droplet has space for more sediment, pick up.
        const float remaining_sediment_capacity_in_droplet = g_droplet_max_sediment - curr_sediment;
        const float to_pick_up_optimal = g_erosion_speed * (sediment_carrying_capacity - curr_sediment);
        float to_pick_up = min(remaining_sediment_capacity_in_droplet, to_pick_up_optimal);

        // Don't flip heights
        to_pick_up = min(to_pick_up, max_terrain_shift);

        next_droplet.position = next_pos_world;
        next_droplet.sediment = to_pick_up;
        next_droplet.energy = curr_droplet.energy - height_diff;
        next_droplet.size = curr_droplet.size * g_evaporation;

        // const inflow_offset_index_x = min(-1, max(1, next_pos_world_x - DTid.x);
        // const inflow_offset_index_y = min(-1, max(1, next_pos_world_x - DTid.x);
        // const inflow_offset_index = inflow_offset_index_x + 3 * inflow_offset_index_y;
        // const inflow_base_index = next_pos_world_x * 8 + next_pos_world_y * 8 * g_in_buffer_width;
        // g_output_buffer_inflow[inflow_base_index + inflow_offset_index] =
    }
    else if (curr_sediment > sediment_carrying_capacity)
    {
        // Droplet full, drop some sediment
        float to_drop = curr_sediment - sediment_carrying_capacity;

        // Don't flip heights
        to_drop = min(to_drop, max_terrain_shift);

        next_droplet.position = next_pos_world;
        next_droplet.sediment = curr_droplet.sediment - to_drop;
        next_droplet.energy = curr_droplet.energy - height_diff;
        next_droplet.size = curr_droplet.size * g_evaporation;
    }

    g_output_buffer_droplets_next[index_self] = next_droplet;

    // Next step: Collate incoming "next" droplets, reset and recalculate curr droplet, update heights.
}
