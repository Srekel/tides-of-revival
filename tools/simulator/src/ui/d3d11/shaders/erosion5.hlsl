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
RWStructuredBuffer<float> g_output_buffer_droplet_energies_new : register(u7); 
RWStructuredBuffer<float> g_output_buffer_droplet_sizes_new : register(u8); 
RWStructuredBuffer<float> g_output_buffer_droplet_sediment_new : register(u9); 

[numthreads(32, 32, 1)] void CSErosion_5_apply_droplets(uint3 DTid : SV_DispatchThreadID)
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
    g_output_buffer_droplet_energies[index_self] = g_output_buffer_droplet_energies_new[index_self];
    g_output_buffer_droplet_sizes[index_self] = g_output_buffer_droplet_sizes_new[index_self];
    g_output_buffer_droplet_sediment[index_self] = g_output_buffer_droplet_sediment_new[index_self];
}
