#define DIRECT3D12
#define STAGE_VERT

#include "terrain_shadow_caster_resources.hlsli"

TerrainShadowVSOutput VS_MAIN(TerrainVSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    TerrainShadowVSOutput Out;
    Out.UV = unpack2Floats(Input.UV);

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = instance_id + g_instanceRootConstants.startInstanceLocation;
    TerrainInstanceData instance = instance_transform_buffer.Load<TerrainInstanceData>(instanceIndex * sizeof(TerrainInstanceData));

    float3 displaced_position = Input.Position.xyz;

    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height = SampleLvlTex2D(heightmap, g_linear_clamp_edge_sampler, Out.UV, 0).r;
    displaced_position.y += height;

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(displaced_position, 1.0f));

    RETURN(Out);
}
