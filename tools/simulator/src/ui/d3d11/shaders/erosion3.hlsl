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
// BL:   ( 0.2 + 0.9 ) / 4  =>  0.275
// BR:   ( 0.8 + 0.9 ) / 4  =>  0.425
// TL:   ( 0.2 + 0.1 ) / 4  =>  0.075
// TR:   ( 0.8 + 0.1 ) / 4  =>  0.225
// SUM:     2 + 2                 1

[numthreads(32, 32, 1)] void CSErosion_3_move_sediment(uint3 DTid : SV_DispatchThreadID) {
    // Skip edges
    const uint range = 2;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2) {
        return;
    }

    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;
    const Droplet self_curr_droplet = g_output_buffer_droplets[index_self];
    Droplet self_next_droplet = g_output_buffer_droplets_next[index_self];
    if (self_next_droplet._padding8 == 1) {
        self_next_droplet._padding8 = 0;
        g_output_buffer_droplets_next[index_self] = self_next_droplet;
        return;
    }

    const float weight_BL = 0.25 * ((1 - self_curr_droplet.position.x) + (1 - self_curr_droplet.position.y));
    const float weight_BR = 0.25 * ((0 + self_curr_droplet.position.x) + (1 - self_curr_droplet.position.y));
    const float weight_TL = 0.25 * ((1 - self_curr_droplet.position.x) + (0 + self_curr_droplet.position.y));
    const float weight_TR = 0.25 * ((0 + self_curr_droplet.position.x) + (0 + self_curr_droplet.position.y));

    const uint index_BL = DTid.x + 0 + (DTid.y + 0) * g_in_buffer_width;
    const uint index_BR = DTid.x + 1 + (DTid.y + 0) * g_in_buffer_width;
    const uint index_TL = DTid.x + 0 + (DTid.y + 1) * g_in_buffer_width;
    const uint index_TR = DTid.x + 1 + (DTid.y + 1) * g_in_buffer_width;

    const float height_BL = g_output_buffer_heightmap[index_BL];
    const float height_BR = g_output_buffer_heightmap[index_BR];
    const float height_TL = g_output_buffer_heightmap[index_TL];
    const float height_TR = g_output_buffer_heightmap[index_TR];

    const float height_diff = self_curr_droplet.sediment - self_next_droplet.sediment;
    g_output_buffer_heightmap[index_BL] = max(0.12345, height_BL + height_diff * weight_BL);
    g_output_buffer_heightmap[index_BR] = max(0.12345, height_BR + height_diff * weight_BR);
    g_output_buffer_heightmap[index_TL] = max(0.12345, height_TL + height_diff * weight_TL);
    g_output_buffer_heightmap[index_TR] = max(0.12345, height_TR + height_diff * weight_TR);

    // if (height_diff > 0.00001)
    {
        // g_output_buffer_debug[index_self] = g_output_buffer_heightmap[index_BL] / 10;
    }
}
