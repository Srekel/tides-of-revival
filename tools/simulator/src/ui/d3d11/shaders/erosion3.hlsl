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

// static const float radius_0_weight_total = 1 * 1; // 1
// static const float weights_radius_0[1] = {
//     1 / radius_0_weight_total,
// };

// // 3x3 grid
// static const float radius_1_weight_total = 1 * 3 + 4 * 2 + 4 * 1; // 15
// static const float weights_radius_1[3] = {
//     (3-0) / radius_1_weight_total,
//     (3-1) / radius_1_weight_total,
//     (3-2) / radius_1_weight_total,
// };

// // 5x5 grid
// static const float radius_2_weight_total = 
// 1 * 5 + // 0
// 4 * 4 + // 1
// 8 * 3 + // 2
// 8 * 2 + // 3
// 4 * 1;  // 4 --> 65

// static const float weights_radius_2[5] = {
//     (5-0) / radius_2_weight_total,
//     (5-1) / radius_2_weight_total,
//     (5-2) / radius_2_weight_total,
//     (5-3) / radius_2_weight_total,
//     (5-4) / radius_2_weight_total,
// };

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
    const int max_radius = 3;
    const uint range = 2 + max_radius;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2) {
        return;
    }

    const float radius_0_weight_total = 1 * 1; // 1
    const float weights_radius_0[1] = {
        1 / radius_0_weight_total,
    };

    // 3x3 grid
    const float radius_1_weight_total = 1 * 3 + 4 * 2 + 4 * 1; // 15
    const float weights_radius_1[3] = {
        (3-0) / radius_1_weight_total,
        (3-1) / radius_1_weight_total,
        (3-2) / radius_1_weight_total,
    };

    // 5x5 grid
    const float radius_2_weight_total = 
    1 * 5 + // 0
    4 * 4 + // 1
    8 * 3 + // 2
    8 * 2 + // 3
    4 * 1;  // 4 --> 65

    const float weights_radius_2[5] = {
        (5-0) / radius_2_weight_total,
        (5-1) / radius_2_weight_total,
        (5-2) / radius_2_weight_total,
        (5-3) / radius_2_weight_total,
        (5-4) / radius_2_weight_total,
    };

    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    float terrain_change = 0;
    const Droplet self_curr_droplet = g_output_buffer_droplets[index_self];
    Droplet self_next_droplet = g_output_buffer_droplets_next[index_self];

    for (int x = int(DTid.x) - max_radius + 1; x <= int(DTid.x) + max_radius - 1; x++) {
        for (int y = int(DTid.y) - max_radius + 1; y <= int(DTid.y) + max_radius - 1; y++) {
            const uint index_nbor = x + y * g_in_buffer_width;
            const Droplet nbor_next_droplet = g_output_buffer_droplets_next[index_nbor]; 

            const int xx = abs(x - int(DTid.x));
            const int yy = abs(y - int(DTid.y));
            const int dist = xx + yy; // manhattan

            // droplet_range goes 0 --> (max_radius - 1)
            const int droplet_range = min(max_radius, floor(1 + sqrt(nbor_next_droplet.size))) - 1;
            if (droplet_range < dist) {
                continue;
            }

            Droplet nbor_curr_droplet = g_output_buffer_droplets[index_nbor];
            const float height_diff = nbor_curr_droplet.sediment - nbor_next_droplet.sediment;
            float weight = 0;
            if (droplet_range == 0) {
                weight = weights_radius_0[0];
            }
            else if (droplet_range == 1) {
                weight = weights_radius_1[dist];
            }
            else if (droplet_range == 2) {
                weight = weights_radius_2[dist];
            }
            else {
                g_output_buffer_debug[index_self] = 10000;
                return;
            }

            const float height_diff_weighted = height_diff * weight;
            terrain_change += height_diff_weighted;
        }
    }

    const float self_height = g_output_buffer_heightmap[index_self];
    g_output_buffer_heightmap[index_self] = max(0.12345, self_height + terrain_change);

    // if (height_diff > 0.00001)
    {
        g_output_buffer_debug[index_self] = max(g_output_buffer_debug[index_self], self_next_droplet.size);
    }
}
