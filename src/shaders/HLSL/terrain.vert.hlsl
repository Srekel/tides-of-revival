#define DIRECT3D12
#define STAGE_VERT

#include "terrain_resources.hlsl"

float inverse_lerp(float value1, float value2, float pos)
{
	return all(value2 == value1) ? 0 : ((pos - value1) / (value2 - value1));
}

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.InstanceID = instance_id;
    Out.UV = unpack2Floats(Input.UV);

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
    Out.Normal = mul((float3x3)instance.worldMat, float3(0, 1, 0));

    RETURN(Out);
}
