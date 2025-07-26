#define DIRECT3D12
#define STAGE_VERT

#include "terrain_gbuffer_resources.hlsli"

TerrainVSOutput VS_MAIN(TerrainVSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    TerrainVSOutput Out;
    Out.InstanceID = instance_id;
    Out.UV = Input.UV;

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = instance_id + g_instanceRootConstants.startInstanceLocation;
    TerrainInstanceData instance = instance_transform_buffer.Load<TerrainInstanceData>(instanceIndex * sizeof(TerrainInstanceData));

    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV, 0).r;
    float3 position = Input.Position.xyz;
    position.y += height;

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(position, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(position, 1.0f)).xyz;

    // Recalculate vertex normal
    // 4-tap solution
    {
        float texelSize = 1.0f / 65.0f;
        float r = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV + float2(texelSize, 0), 0).r;
        float l = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV + float2(-texelSize, 0), 0).r;
        float f = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV + float2(0, texelSize), 0).r;
        float b = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV + float2(0, -texelSize), 0).r;

        float vertexSpacing = 1u << instance.lod;

        float x = (r - l) / (vertexSpacing * 2);
        float z = (f - b) / (vertexSpacing * 2);
        Out.NormalWS = normalize(float3(-x, 1.0, -z));
    }

    RETURN(Out);
}
