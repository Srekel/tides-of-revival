#include "FastNoiseLite.hlsl"

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
    float IS_INITALIZED;
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

float rand2dTo1d(float2 value, float2 dotDir = float2(12.9898, 78.233))
{
    float2 smallValue = sin(value);
    float random = dot(smallValue, dotDir);
    random = frac(sin(random) * 143758.5453);
    return random;
}

float2 rand2dTo2d(float2 value)
{
    return float2(
        rand2dTo1d(value, float2(12.989, 78.233)),
        rand2dTo1d(value, float2(39.346, 11.135)));
}

[numthreads(32, 32, 1)] void CSErosion_1_rain(uint3 DTid : SV_DispatchThreadID) {
    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    const bool first_time = g_output_buffer_droplets[index_self].IS_INITALIZED == 0;
    if (first_time) {
        const float height = g_input_buffer_heightmap[index_self];
        g_output_buffer_heightmap[index_self] = height;
        g_output_buffer_droplets[index_self].IS_INITALIZED = 1.0;
    }

    // Skip edges
    const uint range = 2;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2) {
        g_output_buffer_debug[index_self] = DTid.x % 2 == 0 ? 0 : 255;
        return;
    }

    if (first_time || true) {
        if (g_output_buffer_heightmap[index_self] > 100 && DTid.x % 20 >= 0 && DTid.y % 20 >= 0) {
            if (g_output_buffer_droplets[index_self].size <= 0.00001) {
                const float rain_amount = 1;
                const float total_size = g_output_buffer_droplets[index_self].size + rain_amount;

                const float2 pos_prev = g_output_buffer_droplets[index_self].position;
                const float2 pos_new = float2(0.01, 0.01) + 0.98 * rand2dTo2d(float2(DTid.x, DTid.y));

                g_output_buffer_droplets[index_self].position = lerp(pos_prev, pos_new, rain_amount / total_size);
                g_output_buffer_droplets[index_self].size = total_size;
                g_output_buffer_droplets[index_self].energy = max(1, g_output_buffer_droplets[index_self].energy);
                // g_output_buffer_debug[index_self] = 230;
            }
        }
    }

    // if (g_output_buffer_heightmap[index_self] > 100 && DTid.x % 20 == 0 && DTid.y % 20 == 0)
    // {
    //     g_output_buffer_debug[index_self] = 230;
    // }

    Droplet next_droplet = g_output_buffer_droplets_next[index_self];
    next_droplet.position = float2(0, 0);
    next_droplet.sediment = 0;
    next_droplet.energy = 0;
    next_droplet.size = 0;
    g_output_buffer_droplets_next[index_self] = next_droplet;
}
