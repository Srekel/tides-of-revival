//////////////////////////////
// EROSION
//
//////////////////////////////
// STEP 1
// Rain: Create droplets
//
//                              Self  Neighbours
// droplet_sizes                  W       -
// droplet_positions              W       -
// droplet_energies               W       -
//
//////////////////////////////
// STEP 2:
// Figure out where droplets go, or rather where they come from
// and how much sediment they ought to pick up/drop off
//
//                              Self  Neighbours
// heightmap                      R       R
// droplet_positions              R       R
// droplet_energies               R       R
// droplet_sizes                  R       R
// droplet_sediment               R       R
// Write: inflow                  W       -
// Write: droplet_positions_new   -       W
//
//////////////////////////////
// STEP 3:
// Take the flow and move sediment to/from heightmap and/or droplet
//
//                              Self  Neighbours
// inflow                         R       -
// heightmap                      -       W
// droplet_sediment               -       W
//
//////////////////////////////
// STEP 4:
// Calculate droplet update
// add energy based on height difference
// evaporate
// merge droplets
//
//                              Self  Neighbours
// droplet_positions_new          R       R
// droplet_positions              W       R            !!!
// droplet_energies               R       R
// droplet_sizes                  R       R
// droplet_sediment               R       R
// droplet_positions_new          W       -
// droplet_energies_new           W       -
// droplet_sizes_new              W       -
// droplet_sediment_new           W       -
//////////////////////////////

//////////////////////////////
// STEP 4:
// Apply droplet update
//
//                              Self  Neighbours
// droplet_positions_new          R       -
// droplet_energies_new           R       -
// droplet_sizes_new              R       -
// droplet_sediment_new           R       -
// droplet_positions_new          R       -
// droplet_positions              W       -
// droplet_energies               W       -
// droplet_sizes                  W       -
// droplet_sediment               W       -
//////////////////////////////

// g_output_buffer_heightmap
// world space
//
// g_output_buffer_droplet_positions
// position, [0,1] cell offset space
//
// g_output_buffer_droplet_energies
// "speed" of water
//
// g_output_buffer_droplet_sizes
// how much water is in this cell
//
// g_output_buffer_droplet_sediment
// how much sediment each droplet is currently carrying
//
// g_output_buffer_inflow
// how much sediment should be picked up or dropped off
//
// g_output_buffer_droplet_positions_new
// where each droplets will move to, worldspace

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

[numthreads(32, 32, 1)] void CSErosion_1_rain(uint3 DTid : SV_DispatchThreadID)
{
    const uint index_self = DTid.x + DTid.y * g_in_buffer_width;

    // Skip edges
    const uint range = 2;
    if (DTid.x <= range + 1 ||
        DTid.x >= g_in_buffer_width - range - 2 ||
        DTid.y <= range + 1 ||
        DTid.y >= g_in_buffer_height - range - 2)
    {
        g_output_buffer_debug[index_self] = DTid.x % 2 == 0 ? 0 : 255;
        return;
    }

    // Initialize first time
    if (g_output_buffer_heightmap[index_self] == 0)
    {
        const float height = g_input_buffer_heightmap[index_self];
        g_output_buffer_heightmap[index_self] = height;
        g_output_buffer_debug[index_self] = 255;

        if (height > 100 && rand2dTo1d(float2(DTid.x, DTid.y)) > 0.99)
        {
            const float rain_amount = 1;
            const float total_size = g_output_buffer_droplets[index_self].size + rain_amount;

            const float2 pos_prev = g_output_buffer_droplets[index_self].position;
            const float2 pos_new = rand2dTo2d(float2(DTid.x, DTid.y));

            g_output_buffer_droplets[index_self].position = lerp(pos_prev, pos_new, rain_amount / total_size);
            g_output_buffer_droplets[index_self].size = total_size;
            g_output_buffer_droplets[index_self].energy = 1;
            g_output_buffer_debug[index_self] = 200;
        }
    }

    Droplet next_droplet = g_output_buffer_droplets_next[index_self];
    next_droplet.position = float2(0, 0);
    next_droplet.sediment = 0;
    next_droplet.energy = 0;
    next_droplet.size = 0;
    g_output_buffer_droplets_next[index_self] = next_droplet;
}
