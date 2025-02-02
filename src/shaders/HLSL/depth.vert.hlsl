#define DIRECT3D12
#define STAGE_VERT

#define VL_PosNorTanUv0Col
#include "depth_resources.hlsli"

VSOutput VS_MAIN(VSInput Input, uint instance_id : SV_InstanceID)
{
    INIT_MAIN;
    VSOutput Out;

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = instance_id + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(Input.Position.xyz, 1.0f));

    RETURN(Out);
}