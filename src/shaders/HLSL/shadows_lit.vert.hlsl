#define DIRECT3D12
#define STAGE_VERT

#include "shadows_lit_resources.hlsl"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.InstanceID = instance_id;
    Out.UV = unpack2Floats(Input.UV);

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = instance_id + Get(startInstanceLocation);
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    float4x4 tempMat = mul(Get(projView), instance.worldMat);
    Out.Position = mul(tempMat, float4(Input.Position.xyz, 1.0f));

    RETURN(Out);
}
