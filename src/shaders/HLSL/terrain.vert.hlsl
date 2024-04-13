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

    float4x4 tempMat = mul(Get(projView), instance.worldMat);
    Out.Position = mul(tempMat, float4(displaced_position, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(displaced_position, 1.0f)).xyz;
    // TODO(gmodarelli): We don't need to store normals and tangent in the vertex buffer since terrain tiles are flat
    Out.Normal = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Normal)), 0.0f)).rgb;
    Out.Tangent = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Tangent)), 0.0f)).rgb;

    RETURN(Out);
}
