cbuffer constant_buffer_0 : register(b0)
{
    uint g_in_buffer_width;
    uint g_in_buffer_height;
    float _padding1;
    float _padding2;
};

StructuredBuffer<float> g_input_buffer_heightmap : register(t0);
RWStructuredBuffer<float> g_output_buffer_heightmap : register(u0);
RWStructuredBuffer<float2> g_output_buffer_droplet_positions : register(u1); 
RWStructuredBuffer<float> g_output_buffer_droplet_energies : register(u2); 
RWStructuredBuffer<float> g_output_buffer_droplet_sizes : register(u3); 
RWStructuredBuffer<float> g_output_buffer_droplet_sediment : register(u4); 
RWStructuredBuffer<float> g_output_buffer_inflow : register(u5); 
RWStructuredBuffer<float> g_output_buffer_outflow : register(u6); 

float height_at_pos(uint x, uint y, float2 pos) {
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

float3 height_gradient_at_pos(uint x, uint y, float2 pos) {
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
    
    const float dx_bot = height_bl - height_br;
    const float dx_top = height_tl - height_tr;
    const float dx = lerp(dx_bot, dx_top, droplet_pos.y);
    const float dy_left = height_bl - height_tl;
    const float dy_right = height_br - height_tr;
    const float dy = lerp(dy_left, dy_right, droplet_pos.x);

    return float3(height, dx, dy);
}

[numthreads(32, 32, 1)] void CSErosion_3_do_the_flow(uint3 DTid : SV_DispatchThreadID)
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

            // Do the outflow (from self)
            const uint outflow_neighbour_index = x * 8 + y * 8 * g_in_buffer_width;
            const uint self_relative_index = 7 - inflow_offset_index;
            const float flow_from_self_to_neighbor = g_output_buffer_inflow[outflow_neighbour_index + self_relative_index];
            const float outflow = -flow_from_self_to_neighbor;
            total_flow += outflow;

            // Do the inflow (to self)
            const uint inflow_index = inflow_base_index + inflow_offset_index;
            const float inflow = g_output_buffer_inflow[inflow_index];
            total_flow += inflow;

            inflow_offset_index += 1;
        }
    }

    g_output_buffer_heightmap[index_self] += total_outflow;
}
