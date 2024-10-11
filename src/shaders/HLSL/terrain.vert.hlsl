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

    float3 position = Input.Position.xyz;

    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), Out.UV, 0).r;
    position.y += height;

    // Vertex Spacing
    // LOD0: 1m
    // LOD1: 2m
    // LOD2: 4m
    // LOD3: 8m
    float vertex_spacing = 1u << instance.lod;
    // Recalculate the normal after displacing the vertex
    float3 normal = float3(
        height - SampleLvlTex2D(heightmap, Get(bilinearClampSampler), saturate(Out.UV + float2(1.0f / 65.0f, 0.0f)), 0).r,
        vertex_spacing,
        height - SampleLvlTex2D(heightmap, Get(bilinearClampSampler), saturate(Out.UV + float2(0.0f, 1.0f / 65.0f)), 0).r
    );
    normal = normalize(normal);

    float4x4 tempMat = mul(Get(projView), instance.worldMat);
    Out.Position = mul(tempMat, float4(position, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(position, 1.0f)).xyz;
    Out.Normal = normal;

    RETURN(Out);
}
