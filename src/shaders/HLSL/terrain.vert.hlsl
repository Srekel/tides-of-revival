#define DIRECT3D12
#define STAGE_VERT

#include "terrain_resources.hlsl"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.InstanceID = instance_id;
    Out.UV = unpack2Floats(Input.UV);

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = instance_id + Get(startInstanceLocation);
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    float3 displaced_position = Input.Position.xyz;

    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), Out.UV, 0).r;
    displaced_position.y += height;

    // Recalculate the normal after displacing the vertex
    height = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), Out.UV + float2(0.01f, 0.0f), 0).r;
    float3 neighbour = float3(Input.Position.x + 1.0f, Input.Position.y + height, Input.Position.z);
    float3 tangent = normalize(neighbour - displaced_position);

    height = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), Out.UV + float2(0.0f, -0.01f), 0).r;
    neighbour = float3(Input.Position.x, Input.Position.y + height, Input.Position.z - 1.0f);
    float3 bitangent = normalize(neighbour - displaced_position);

    float3 normal = normalize(cross(tangent, bitangent));

    float4x4 tempMat = mul(Get(projView), instance.worldMat);
    Out.Position = mul(tempMat, float4(displaced_position, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(displaced_position, 1.0f)).xyz;
    Out.Normal = mul((float3x3)instance.worldMat, normal);
    Out.Tangent = mul((float3x3)instance.worldMat, tangent);

    RETURN(Out);
}
