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
RWStructuredBuffer<Droplet> g_output_buffer_droplets_new : register(u2); 
RWStructuredBuffer<float> g_output_buffer_inflow : register(u3); 

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
    // for (uint y = DTid.y - 1; y <= DTid.y + 1; y++) {
    //     for (uint x = DTid.x - 1; x <= DTid.x + 1; x++) {
    for (uint yy = 0; yy <= 2; yy++) {
        for (uint xx = 0; xx <= 2; xx++) {
            const uint x = DTid.x + xx - 1;
            const uint y = DTid.y + yy - 1;
            // g_output_buffer_heightmap[index_self] = 1000;
            if (x == DTid.x && y == DTid.y) {
                continue;
            }

            ////////////////////////////////////////////////////////////
            // Do the inflow (to self)
            const uint index_neighbor = x + y * g_in_buffer_width;
            const uint inflow_index = inflow_base_index + inflow_offset_index;
            const float inflow = g_output_buffer_inflow[inflow_index];
            const float droplet_sediment = g_output_buffer_droplets[index_neighbor].sediment;
            if (inflow > 0) {
                // Pick up sediment
                const float sediment_to_pick_up = min(g_droplet_max_sediment - droplet_sediment, inflow);
                g_output_buffer_heightmap[index_neighbor] -= min(g_output_buffer_heightmap[index_neighbor], sediment_to_pick_up);
                g_output_buffer_droplets[index_neighbor].sediment += sediment_to_pick_up;
                // g_output_buffer_heightmap[index_neighbor] = 100;
            }
            else if (inflow < 0) {
                // Drop off sediment
                const float sediment_to_drop = min(droplet_sediment, -inflow);
                g_output_buffer_heightmap[index_neighbor] += sediment_to_drop;
                g_output_buffer_droplets[index_neighbor].sediment -= sediment_to_drop;
                // g_output_buffer_heightmap[index_neighbor] = 10;
            }
            // else {
            //     g_output_buffer_heightmap[index_neighbor] = 50;
            // }

            inflow_offset_index += 1;
        }
    }

    // TODO: "The height change is applied to the terrain through bilinear 
    // interpolation, depending on the droplet’s position within its cell."

    // float height = g_output_buffer_heightmap[index_self];
    // height += total_flow;
    // height = max(0, height);
    // g_output_buffer_heightmap[index_self] = height;
}
