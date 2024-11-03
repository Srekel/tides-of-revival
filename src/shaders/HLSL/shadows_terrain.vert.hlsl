#define DIRECT3D12
#define STAGE_VERT

#include "shadows_terrain_resources.hlsl"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.UV = unpack2Floats(Input.UV);

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instance_data_buffer_index];
    uint instanceIndex = instance_id + g_start_instance_location;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    float3 displaced_position = Input.Position.xyz;

    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height = SampleLvlTex2D(heightmap, g_linear_clamp_edge_sampler, Out.UV, 0).r;
    displaced_position.y += height;

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(displaced_position, 1.0f));

    RETURN(Out);
}
