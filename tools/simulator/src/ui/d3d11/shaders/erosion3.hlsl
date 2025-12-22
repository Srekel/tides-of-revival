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
    const uint inflow_base_index = DTid.x * 8 + DTid.y * 8 * g_in_buffer_width;
    const uint inflow_offset_index = 0;

    float total_flow = 0;
    for (uint y = DTid.y - 1; y <= DTid.y + 1; y++) {
        for (uint x = DTid.x - 1; x <= DTid.x + 1; x++) {
            if (x == DTid.x && y == DTid.y) {
                continue;
            }

            ////////////////////////////////////////////////////////////
            // Do the outflow (from self)
            // I.e. we subtract the outflow here and assume that it gets added by the target cell.
            // It may also be that our droplet is in fact dropping sediment here (i.e. adding).
            // Same logic regardless.
            // 
            // Given this neighbor, we check its inflow buffer. We calculate our index to look up 
            // how much we have determined should be picked up (or dropped off).
            const uint outflow_neighbour_index = x * 8 + y * 8 * g_in_buffer_width;
            const uint self_relative_index = 7 - inflow_offset_index;
            const float flow_from_self_to_neighbor = g_output_buffer_inflow[outflow_neighbour_index + self_relative_index];
            const float outflow = -flow_from_self_to_neighbor;
            total_flow += outflow;

            ////////////////////////////////////////////////////////////
            // Do the inflow (to self)
            const uint inflow_index = inflow_base_index + inflow_offset_index;
            const float inflow = g_output_buffer_inflow[inflow_index];
            total_flow += inflow;

            inflow_offset_index += 1;
        }
    }

    // TODO: "The height change is applied to the terrain through bilinear 
    // interpolation, depending on the droplet’s position within its cell."

    float height = g_output_buffer_heightmap[index_self];
    height += total_flow;
    height = max(0, height);
    g_output_buffer_heightmap[index_self] = height;
}
