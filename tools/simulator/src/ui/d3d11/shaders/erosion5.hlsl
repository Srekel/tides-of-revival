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

[numthreads(32, 32, 1)] void CSErosion_5_apply_droplets(uint3 DTid : SV_DispatchThreadID) {
    // Skip edges
    const uint range = 2;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2) {
        return;
    }

    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    // const float curr_energy = g_output_buffer_droplets[index_self].energy;
    // const float curr_size = g_output_buffer_droplets[index_self].size;
    // const float curr_sediment = g_output_buffer_droplets[index_self].sediment;

    // const float next_energy = g_output_buffer_droplets_next[index_self].energy;
    // const float next_size = g_output_buffer_droplets_next[index_self].size;
    // const float next_sediment = g_output_buffer_droplets_next[index_self].sediment;

    // g_output_buffer_droplets[index_self].energy = max(0, curr_energy - next_energy);
    // g_output_buffer_droplets[index_self].size = max(0, curr_size - next_size);
    // g_output_buffer_droplets[index_self].sediment = max(0, curr_sediment - next_sediment);

    // g_output_buffer_debug[index_self] = max(g_output_buffer_debug[index_self], curr_sediment * 10);
}
