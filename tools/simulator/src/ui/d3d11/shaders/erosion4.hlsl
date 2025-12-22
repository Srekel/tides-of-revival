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
    

    // Loop over neighbors
    // old = where it came from (neighbor)
    // new = where it ended up (either self or ignored)
    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;
    const uint index_new = index_self;
    const float2 droplet_pos_self = g_output_buffer_droplet_positions[index_self];

    // Assume all water flowed away
    // TODO: Account for droplets staying..?
    // Noooo can't do this here fffffffffffffffuuuuuuuuuuuuuuuuuuuu
    g_output_buffer_droplet_sizes[index_new] = 0;
    
    for (uint y = DTid.y - 1; y <= DTid.y + 1; y++) {
        for (uint x = DTid.x - 1; x <= DTid.x + 1; x++) {
            const uint index_old = x + y * g_in_buffer_width;
            const float2 droplet_pos_new = g_output_buffer_droplet_positions_new[index_old];
            const uint droplet_pos_new_x = uint(floor(droplet_pos_new.x));
            const uint droplet_pos_new_y = uint(floor(droplet_pos_new.y));
            if (droplet_pos_new_x == DTid.x && droplet_pos_new_y == DTid.y) {
                // Droplet from neighbor ended up here in self
                float size_old = g_output_buffer_droplet_sizes[index_old];
                float size_new = g_output_buffer_droplet_sizes[index_new];
                float size_total = size_old + size_new;

                // Position
                const float2 droplet_pos_new_offset = float2(droplet_pos_new.x - droplet_pos_new_x, droplet_pos_new.y - droplet_pos_new_y);
                const float droplet_pos = lerp(droplet_pos_self, droplet_pos_offset, size_new / size_total);
                g_output_buffer_droplet_positions[index_new] = droplet_pos_new_offset;

                // Energy
                const float2 droplet_pos_old = g_output_buffer_droplet_positions[index_old];
                const float height_old = height_at_pos(x, y, droplet_pos_old);
                const float height_new = height_at_pos(DTid.x, DTid.y, droplet_pos_new_offset);
                const float height_difference = height_old - height_new;
                const float energy_old = g_output_buffer_droplet_energies[index_old];
                float energy = g_output_buffer_droplet_energies[index_new];
                if (height_difference >= 0) {
                    // Tried to go upwards
                    energy = 0;
                }
                else {
                    const float gravity = 1;
                    energy += height_difference * gravity;
                }
                
                energy = lerp(energy_old, energy, size_new / size_total);
                g_output_buffer_droplet_energies[index_new] = energy;

                // Size
                size_total *= g_evaporation;
                g_output_buffer_droplet_sizes[index_new] = size_total;

                // Sediment
                g_output_buffer_droplet_sediment[index_new] += g_output_buffer_droplet_sediment[index_old];
            }
        }
    }
}
