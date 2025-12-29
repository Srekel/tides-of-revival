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
// RWStructuredBuffer<float> g_output_buffer_inflow : register(u3);
RWStructuredBuffer<float> g_output_buffer_debug : register(u3);

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
    if (height_diff > 0.001)
    {
        g_output_buffer_debug[index_self] = height / 10;
    }
}
