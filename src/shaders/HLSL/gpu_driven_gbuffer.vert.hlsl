#define DIRECT3D12
#define STAGE_VERT

#include "gpu_driven_gbuffer_resources.hlsli"

VSOutput VS_MAIN(
    uint instanceId : SV_InstanceID,
    uint vertexId : SV_VertexId,
    uint startVertexLocation : SV_StartVertexLocation,
    uint startInstanceLocation : SV_StartInstanceLocation)
{
    uint instanceIndex = instanceId + startInstanceLocation;
    uint vertexIndex = vertexId + startVertexLocation;

    VSOutput Out;
    Out.InstanceID = instanceIndex;

    ByteAddressBuffer instanceIndirectionBuffer = ResourceDescriptorHeap[g_InstanceIndirectionBufferIndex];
    InstanceIndirectionData instanceIndirection = instanceIndirectionBuffer.Load<InstanceIndirectionData>(instanceIndex * sizeof(InstanceIndirectionData));

    ByteAddressBuffer instanceBuffer = ResourceDescriptorHeap[g_InstanceBufferIndex];
    InstanceData instance = instanceBuffer.Load<InstanceData>(instanceIndirection.instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer vertexBuffer = ResourceDescriptorHeap[g_VertexBufferIndex];
    Vertex vertex = vertexBuffer.Load<Vertex>(vertexIndex * sizeof(Vertex));

    float4x4 tempMat = mul(g_ProjView, instance.worldMat);
    Out.Position = mul(tempMat, float4(vertex.position, 1.0f));
    Out.Normal = normalize(mul((float3x3)instance.worldMat, vertex.normal));
    Out.Tangent.xyz = normalize(mul((float3x3)instance.worldMat, vertex.tangent.xyz));
    Out.Tangent.w = vertex.tangent.w;
    Out.UV = vertex.uv;

    RETURN(Out);
}
