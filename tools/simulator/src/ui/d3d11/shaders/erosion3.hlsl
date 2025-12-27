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

[numthreads(32, 32, 1)] void CSErosion_3_move_sediment(uint3 DTid : SV_DispatchThreadID)
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

    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    const Droplet self_curr_droplet = g_output_buffer_droplets[index_self];
    const Droplet self_next_droplet = g_output_buffer_droplets_next[index_self];

    const float height_diff = self_curr_droplet.sediment - self_next_droplet.sediment;
    const float height = g_output_buffer_heightmap[index_self];
    g_output_buffer_heightmap[index_self] = max(0, height + height_diff);

    // const uint inflow_base_index = DTid.x * 9 + DTid.y * 9 * g_in_buffer_width;
    // const uint inflow_offset_index = 0;

    // float total_flow = 0;
    // for (uint y = DTid.y - 1; y <= DTid.y + 1; y++) {
    //     for (uint x = DTid.x - 1; x <= DTid.x + 1; x++) {
    // float height_change_total = 0;
    // for (uint yy = 0; yy <= 2; yy++)
    // {
    //     for (uint xx = 0; xx <= 2; xx++)
    //     {
    //         const uint x = DTid.x + xx - 1;
    //         const uint y = DTid.y + yy - 1;
    //         const uint index_nbor = x + y * g_in_buffer_width;
    //         const Droplet nbor_curr_droplet = g_output_buffer_droplets_next[index_nbor];
    //         const Droplet nbor_next_droplet = g_output_buffer_droplets_next[index_nbor];
    //         const uint nbor_next_pos_world_x = uint(floor(next_pos_world.x));
    //         const uint nbor_next_pos_world_y = uint(floor(next_pos_world.y));

    //         if (uint(floor(nbor_next_droplet.position.x)) != x || uint(floor(nbor_next_droplet.position.y)) != y)
    //         {
    //             // Neighbor didn't flow into self
    //             continue;
    //         }

    //         // float height_change = nbor_next_droplet.sediment

    //         // const float nbor_size = nbor_next_droplet.size;
    //         // const float total_size = nbor_size + self_next_droplet.size - self_curr_droplet.size;
    //         // self_curr_droplet.position = lerp(self_curr_droplet.position, nbor_next_droplet.position, nbor_size / total_size);
    //         // self_curr_droplet.energy += nbor_next_droplet.energy;
    //         // self_curr_droplet.size += nbor_next_droplet.size;
    //         // self_curr_droplet.sediment += nbor_next_droplet.sediment;
    //     }
    // }

    // TODO: "The height change is applied to the terrain through bilinear
    // interpolation, depending on the droplet’s position within its cell."

    // float height = g_output_buffer_heightmap[index_self];
    // height += total_flow;
    // height = max(0, height);
    // g_output_buffer_heightmap[index_self] = height;
}
