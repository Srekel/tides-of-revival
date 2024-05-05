#define DIRECT3D12
#define STAGE_VERT

#define VL_PosNorTanUv0ColUV1
#include "shadows_tree_resources.hlsl"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.InstanceID = instance_id;
    Out.UV = unpack2Floats(Input.UV);
    Out.UV1 = Input.UV1;

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = instance_id + Get(startInstanceLocation);
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    float3 positionOS = Input.Position.xyz;
    float3 positionWS = mul(instance.worldMat, float4(positionOS, 1.0f)).xyz;
    float3 normalWS = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Normal)), 0.0f)).xyz;

    if (material.windFeature) {
        // Wind
        float3 rootWP = mul(instance.worldMat, float4(0, 0, 0, 1)).xyz;

        WindData windData;
        ApplyWindDisplacement(positionWS, windData, normalWS, rootWP, material.windStifness, material.windDrag, material.windInitialBend, Get(time));
        positionOS = mul(instance.worldMatInverted, float4(positionWS, 1.0f)).xyz;
    }

    float4x4 mvp = mul(Get(projView), instance.worldMat);
    Out.Position = mul(mvp, float4(positionOS, 1.0f));

    RETURN(Out);
}
