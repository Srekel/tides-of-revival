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

    Texture2D normalmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.normalmapTextureIndex)];
    float3 normal = normalize(normalmap.SampleLevel(g_linear_repeat_sampler, Input.UV, 0).rgb * 2.0 - 1.0);
    Out.Normal = mul((float3x3)instance.worldMat, normal);

    RETURN(Out);
}
