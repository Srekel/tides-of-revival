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

    // Super-duper simple normal calculations
    {
        float texelSize = 1.0f / 65.0f;
        float vertexSpacing = 1u << instance.lod;

        float heightRight = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV + float2(texelSize, 0), 0).r;
        float3 positionRightWS = float3(Input.Position.x + vertexSpacing, Input.Position.y + heightRight, Input.Position.z);
        positionRightWS = mul(instance.worldMat, float4(positionRightWS, 1.0f)).xyz;

        float heightForward = heightmap.SampleLevel(g_linear_clamp_edge_sampler, Out.UV + float2(0, texelSize), 0).r;
        float3 positionForwardWS = float3(Input.Position.x, Input.Position.y + heightForward, Input.Position.z + vertexSpacing);
        positionForwardWS = mul(instance.worldMat, float4(positionForwardWS, 1.0f)).xyz;

        float3 tangent = normalize(positionForwardWS - Out.PositionWS);
        float3 bitangent = normalize(positionRightWS - Out.PositionWS);

        Out.NormalWS = normalize(cross(tangent, bitangent));
    }

    RETURN(Out);
}
