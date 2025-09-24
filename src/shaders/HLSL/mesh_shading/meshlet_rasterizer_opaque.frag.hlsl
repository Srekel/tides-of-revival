#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

GBufferOutput main(VertexAttribute vertex, PrimitiveAttribute primitive)
{
    ByteAddressBuffer visibleMeshletBuffer = ResourceDescriptorHeap[g_RasterizerParams.visibleMeshletsBufferIndex];
    MeshletCandidate candidate = visibleMeshletBuffer.Load<MeshletCandidate>(primitive.candidateIndex * sizeof(MeshletCandidate));
    Instance instance = getInstance(candidate.instanceId);
    MaterialData material = getMaterial(instance.materialIndex);

    float3 albedo = material.albedoColor.rgb;
    if (material.albedoTextureIndex != 0xFFFFFFFF)
    {
        Texture2D<float4> albedo_texture = ResourceDescriptorHeap[NonUniformResourceIndex(material.albedoTextureIndex)];
        SamplerState sampler = SamplerDescriptorHeap[g_Frame.linearRepeatSamplerIndex];
        float4 albedo_sample = albedo_texture.Sample(sampler, vertex.uv);
        albedo *= albedo_sample.rgb;
    }

    GBufferOutput Out;
    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(0.0f, 1.0f, 0.0f, 1.0f);
    Out.GBuffer2 = float4(1.0f, 0.04f, 0.0f, 0.5f);

    return Out;
}