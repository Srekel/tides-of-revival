#include "../FSL/d3d.h"

cbuffer RootConstant : register(b0)
{
	uint g_heightmap_texture_index;
	uint g_normalmap_texture_index;
	uint g_texture_resolution;
    uint g_lod;
};

SamplerState g_linear_clamp_edge_sampler : register(s0, UPDATE_FREQ_PER_FRAME);

[numthreads(8, 8, 1)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
    if (thread_id.x >= g_texture_resolution || thread_id.y >= g_texture_resolution) {
        return;
    }

    Texture2D<float> heightmap = ResourceDescriptorHeap[g_heightmap_texture_index];
    RWTexture2D<float4> normalmap = ResourceDescriptorHeap[g_normalmap_texture_index];

    // Vertex Spacing
    // LOD0: 1m
    // LOD1: 2m
    // LOD2: 4m
    // LOD3: 8m
    float vertex_spacing = 1u << g_lod;

    float zb = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(0, -1)).r;
    float zc = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(1, -1)).r;
    float zd = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(1, 0)).r;
    float ze = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(1, 1)).r;
    float zf = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(0, 1)).r;
    float zg = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(-1, 1)).r;
    float zh = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(-1, 0)).r;
    float zi = heightmap.SampleLevel(g_linear_clamp_edge_sampler, thread_id.xy / (float)g_texture_resolution, 0, int2(-1, -1)).r;

    float x = zg + 2 * zh + zi - zc - 2 * zd - ze;
    float z = 2 * zb + zc + zi - ze - 2 * zf - zg;
    float y = 8.0f * vertex_spacing;
    float3 normal = normalize(float3(x, y, z));

    normalmap[thread_id.xy] = float4(normal * 0.5 + 0.5, 1.0);
}