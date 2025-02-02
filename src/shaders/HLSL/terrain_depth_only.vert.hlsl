#define DIRECT3D12
#define STAGE_VERT

#include "terrain_gbuffer_resources.hlsli"

TerrainVSOutput VS_MAIN(TerrainVSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    TerrainVSOutput Out = (TerrainVSOutput)0;

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = instance_id + g_instanceRootConstants.startInstanceLocation;
    TerrainInstanceData instance = instance_transform_buffer.Load<TerrainInstanceData>(instanceIndex * sizeof(TerrainInstanceData));

    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV, 0).r;
    float3 position = Input.Position.xyz;
    position.y += height;

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(position, 1.0f));

    RETURN(Out);
}
