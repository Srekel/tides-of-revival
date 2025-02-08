#define DIRECT3D12
#define STAGE_VERT

#include "water_resources.hlsl"
#include "../FSL/ShaderUtilities.h.fsl"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    VSOutput Out;
    Out.InstanceID = instance_id;
    Out.UV = Input.UV;

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instance_index = instance_id + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instance_index * sizeof(InstanceData));

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(Input.Position.xyz, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(Input.Position.xyz, 1.0f)).xyz;
    Out.Normal = mul(instance.worldMat, float4(Input.Normal, 0.0f)).rgb;
    Out.Tangent.xyz = mul((float3x3)instance.worldMat, Input.Tangent.xyz);
    Out.Tangent.w = Input.Tangent.w;

    return Out;
}