#define DIRECT3D12
#define STAGE_VERT

#define VL_PosNorTanUv0ColUV1
#include "tree_gbuffer_resources.hlsli"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;
    Out.Color = Input.Color;
    Out.InstanceID = instance_id;
    Out.UV = Input.UV;
    Out.UV1 = Input.UV1;

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = instance_id + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[g_instanceRootConstants.materialBufferIndex];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    float3 positionOS = Input.Position.xyz;
    float3 positionWS = mul(instance.worldMat, float4(positionOS, 1.0f)).xyz;
    float3 normalWS = mul(instance.worldMat, float4(Input.Normal, 0.0f)).xyz;

    if (material.windFeature)
    {
        // Wind
        float3 rootWP = mul(instance.worldMat, float4(0, 0, 0, 1)).xyz;

        WindData windData;
        ApplyWindDisplacement(positionWS, windData, normalWS, rootWP, material.windStifness, material.windDrag, material.windInitialBend, g_time);
        positionOS = mul(instance.worldMatInverted, float4(positionWS, 1.0f)).xyz;
    }

    float4x4 mvp = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(mvp, float4(positionOS, 1.0f));
    Out.PositionWS = positionWS;
    Out.Normal = normalWS;
    Out.Tangent.xyz = mul((float3x3)instance.worldMat, Input.Tangent.xyz);
    Out.Tangent.w = Input.Tangent.w;

    RETURN(Out);
}
