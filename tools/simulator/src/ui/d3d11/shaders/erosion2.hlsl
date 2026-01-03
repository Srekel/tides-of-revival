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
RWStructuredBuffer<float2> g_output_buffer_momentum : register(u3);
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

// 
//    |         |         |
// ---┼---------┼---------┼---
//    |         |         |
//    |   200   |   100   |
//    |         |         |
// ---TL--------TR--------┼---
//    |         |         |
//    |   100   |   150   |
//    |      ╳  |         |
// --[BL]-------BR--------┼---
//    |         |         |
// 
//  ╳ = droplet_pos = (0.8, 0.1)
// 

    const float dx_bot = height_bl - height_br;              // -50
    const float dx_top = height_tl - height_tr;              //  100
    const float dx = lerp(dx_bot, dx_top, droplet_pos.y);    // -50 + 150 * 10% = -35
    const float dy_left = height_bl - height_tl;             // -100
    const float dy_right = height_br - height_tr;            // 50
    const float dy = lerp(dy_left, dy_right, droplet_pos.x); // -100 + 150 * 80% = 20

    return float2(dx, dy);
}

float length_squared(float2 vec)
{
    return vec.x * vec.x + vec.y * vec.y;
}

float rand2dTo1d(float2 value, float2 dotDir = float2(12.9898, 78.233))
{
    float2 smallValue = sin(value);
    float random = dot(smallValue, dotDir);
    random = frac(sin(random) * 143758.5453);
    return random;
}

float2 rand2dTo2d(float2 value)
{
    return float2(
        rand2dTo1d(value, float2(12.989, 78.233)),
        rand2dTo1d(value, float2(39.346, 11.135)));
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
    float2 curr_gradient = height_gradient_at_pos(DTid.x, DTid.y, curr_droplet.position, curr_droplet_height);
    if (length_squared(curr_gradient) < 0.001)
    {
        // Flat land
        // float to_drop = curr_sediment * 0.01;

        // const float2 velocity = next_droplet.position;
        // curr_gradient = velocity;

        // const float2 curr_cell_pos = float2(DTid.x, DTid.y);
        // next_droplet.position = curr_cell_pos + curr_droplet.position + velocity;
        // // next_droplet.position = next_pos_world - curr_gradient_01 * 0.5;
        // // next_droplet.sediment = curr_droplet.sediment - to_drop;
        // // next_droplet.energy *= 0.5;
        // // next_droplet.size = curr_droplet.size * g_evaporation;
        // // g_output_buffer_droplets_next[index_self] = next_droplet;

        // next_droplet.position = float2(0, 0);
        // next_droplet.sediment = 0;
        // next_droplet.energy = 0;
        // next_droplet.size = 0;
        // g_output_buffer_droplets_next[index_self] = next_droplet;

        // g_output_buffer_debug[index_self] = 150;
        return;
    }

    const float2 curr_gradient_01 = 0.99 * normalize(normalize(curr_gradient) + rand2dTo2d(curr_gradient) * 0.5);
    const float2 curr_cell_pos = float2(DTid.x, DTid.y);
    const float2 next_pos_world = curr_cell_pos + curr_droplet.position + curr_gradient_01;
    const uint2 next_pos_cell = uint2(floor(next_pos_world));

    const float2 next_droplet_position_offset = next_pos_world - next_pos_cell;
    float next_droplet_height = 0;
    const float2 next_gradient = height_gradient_at_pos(next_pos_cell.x, next_pos_cell.y, next_droplet_position_offset, next_droplet_height);
    const float height_diff = next_droplet_height - curr_droplet_height;
    const bool flowing_downhill = height_diff <= 0;

    const float curr_sediment = curr_droplet.sediment;
    const float max_terrain_shift = abs(height_diff * 0.5 * 0.25); // worst case 4 neighbors pouring into one

    const float energy_added = -height_diff;
    const float energy_next = curr_droplet.energy * energy_added;
    const float sediment_carrying_capacity = flowing_downhill ? curr_size * energy_next * g_sediment_capacity_factor : 0;

    if (!flowing_downhill)
    {
        // Droplet full, drop some sediment
        float to_drop = curr_sediment * 0.1;

        // Don't flip heights
        to_drop = min(to_drop, max_terrain_shift);

        next_droplet.position = next_pos_world - curr_gradient_01 * 0.5;
        next_droplet.sediment = curr_droplet.sediment - to_drop;
        next_droplet.energy *= 0.5;
        next_droplet.size = curr_droplet.size * g_evaporation;

        // g_output_buffer_debug[index_self] = 150;
    }
    else if (curr_sediment <= sediment_carrying_capacity)
    {
        // Flowing down, droplet has space for more sediment, pick up.
        const float to_pick_up_optimal = g_erosion_speed * sediment_carrying_capacity;

        // Don't flip heights
        const float to_pick_up = min(to_pick_up_optimal, max_terrain_shift);

        next_droplet.position = next_pos_world; // yes store world
        next_droplet.sediment = min(curr_sediment + to_pick_up, g_droplet_max_sediment * curr_droplet.size);
        next_droplet.energy = curr_droplet.energy - height_diff;
        next_droplet.size = curr_droplet.size * g_evaporation;
        // g_output_buffer_debug[index_self] = 190;
        // g_output_buffer_debug[index_self] = max(g_output_buffer_debug[index_self], next_droplet.sediment * 1000);
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
        // g_output_buffer_debug[index_self] = 110;
    }

    g_output_buffer_droplets_next[index_self] = next_droplet;
}
