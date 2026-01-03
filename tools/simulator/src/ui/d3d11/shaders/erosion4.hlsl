cbuffer constant_buffer_0 : register(b0) {
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float g_sediment_capacity_factor;
    float g_droplet_max_sediment;
    float g_deposit_speed;
    float g_erosion_speed;
    float g_evaporation;
    float g_momentum;
};

struct Droplet {
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

[numthreads(32, 32, 1)] void CSErosion_4_calculate_droplets(uint3 DTid : SV_DispatchThreadID) {
    // Skip edges
    const uint range = 2;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2) {
        return;
    }

    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    Droplet self_curr_droplet = g_output_buffer_droplets[index_self];
    const float2 prev_pos = self_curr_droplet.position;

    self_curr_droplet.position = float2(0,0); // this is fine because we also set size to 0.
    self_curr_droplet.energy = 0;
    self_curr_droplet.size = 0;
    self_curr_droplet.sediment = 0;

    float energy = 0;
    float2 position = float2(0,0);
    int nbor_count = 0;

    for (int yy = 0; yy <= 2; yy++) {
        for (int xx = 0; xx <= 2; xx++) {
            const int x = DTid.x + xx - 1;
            const int y = DTid.y + yy - 1;
            const int index_nbor = x + y * g_in_buffer_width;
            const Droplet nbor_next_droplet = g_output_buffer_droplets_next[index_nbor];
            if (nbor_next_droplet.size < 0.0001) {
                continue;
            }

            const int2 nbor_next_pos_world = int2(floor(nbor_next_droplet.position));

            if (nbor_next_pos_world.x != DTid.x || nbor_next_pos_world.y != DTid.y) {
                // Neighbor didn't flow into self
                continue;
            }

            nbor_count += 1;

            const float nbor_size = nbor_next_droplet.size;
            const float total_size = nbor_size + self_curr_droplet.size;
            const float lerp_t = nbor_size / total_size;

            // Convert from world space to cell space (0,1)
            const float2 nbor_next_pos = nbor_next_droplet.position - nbor_next_pos_world;

            position += nbor_next_pos;
            energy += nbor_next_droplet.energy;
            self_curr_droplet.size += nbor_next_droplet.size;
            self_curr_droplet.sediment += nbor_next_droplet.sediment;
        }
    }

    if (nbor_count > 0) {
        energy = energy / nbor_count;
        position = position / nbor_count;
    }

    const float2 momentum = position - prev_pos;

    self_curr_droplet.position = position;
    self_curr_droplet.energy = energy;

    g_output_buffer_momentum[index_self] = momentum;
    g_output_buffer_droplets[index_self] = self_curr_droplet;
}
