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

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[g_instance_data_buffer_index];
    uint instanceIndex = instance_id + g_start_instance_location;
    InstanceData instance = instance_transform_buffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    float4x4 tempMat = mul(g_proj_view_mat, instance.worldMat);
    Out.Position = mul(tempMat, float4(Input.Position.xyz, 1.0f));
    Out.PositionWS = mul(instance.worldMat, float4(Input.Position.xyz, 1.0f)).xyz;
    Out.Normal = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Normal)), 0.0f)).rgb;
    // Out.Tangent = mul(instance.worldMat, float4(decodeDir(unpackUnorm2x16(Input.Tangent)), 0.0f)).rgb;
    Out.Tangent.xyz = mul((float3x3)instance.worldMat, Input.Tangent.xyz);
    Out.Tangent.w = Input.Tangent.w;

    RETURN(Out);
}
