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

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = instance_id + Get(startInstanceLocation);
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));


    Texture2D heightmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.heightmapTextureIndex)];
    float height_0 = heightmap.SampleLevel(Get(bilinearClampSampler), Out.UV, 0).r;
    float height_1 = heightmap.SampleLevel(Get(bilinearClampSampler), Out.UV, 0, int2(1, 0)).r;
    float height_2 = heightmap.SampleLevel(Get(bilinearClampSampler), Out.UV, 0, int2(0, 1)).r;

    float3 position = Input.Position.xyz;
    position.y += height_0;

    // Vertex Spacing
    // LOD0: 1m
    // LOD1: 2m
    // LOD2: 4m
    // LOD3: 8m
    float vertex_spacing = 1u << instance.lod;
    float3 p0 = float3(0, height_0, 0);
    float3 p1 = float3(vertex_spacing, height_1, 0);
    float3 p2 = float3(0, height_2, vertex_spacing);
    float3 normal = normalize(cross(p2 - p0, p1 - p0));

    float4x4 tempMat = mul(Get(projView), instance.worldMat);
    Out.Position = mul(tempMat, float4(position, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(position, 1.0f)).xyz;
    Out.Normal = mul((float3x3)instance.worldMat, normal);

    RETURN(Out);
}
