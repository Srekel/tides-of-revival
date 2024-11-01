#include "FastNoiseLite.hlsl"

cbuffer cb0 : register(b0)
{
    uint g_buffer_width;
    uint g_buffer_height;
    int g_seed;
    float g_frequency;
    uint g_octaves;
    float g_scale;
    float2 _padding;
};

RWStructuredBuffer<float> g_output_buffer;

[numthreads(32, 32, 1)]
void CSGenerateFBM(uint3 DTid : SV_DispatchThreadID)
{
    if (DTid.x < g_buffer_width && DTid.y < g_buffer_height)
    {
        fnl_state state = fnlCreateState(g_seed);
        state.fractal_type = FNL_FRACTAL_FBM;
        state.frequency = g_frequency;
        state.octaves = g_octaves;

        float noise = saturate(fnlGetNoise2D(state, DTid.x * g_scale, DTid.y * g_scale) * 0.5f + 0.5f);
        g_output_buffer[DTid.x + DTid.y * g_buffer_width] = noise;
    }
}
