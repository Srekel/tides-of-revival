#define DIRECT3D12
#define STAGE_VERT

#define VL_PosNorTanUv0Col
#include "lit_resources.hlsl"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.Color = Input.Color;
    Out.InstanceID = instance_id;
    Out.UV = unpack2Floats(Input.UV);

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = instance_id + Get(startInstanceLocation);
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    float4x4 tempMat = mul(Get(projView), instance.worldMat);
    Out.Position = mul(tempMat, float4(Input.Position.xyz, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(Input.Position.xyz, 1.0f)).xyz;
    Out.Normal = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Normal)), 0.0f)).rgb;
    Out.Tangent = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Tangent)), 0.0f)).rgb;

    RETURN(Out);
}
