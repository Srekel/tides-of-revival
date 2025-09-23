#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

GBufferOutput main(VertexAttribute vertex, PrimitiveAttribute primitive)
{
    ByteAddressBuffer visible_meshlet_buffer = ResourceDescriptorHeap[g_rasterizer_params.visible_meshlets_buffer_index];
    MeshletCandidate candidate = visible_meshlet_buffer.Load<MeshletCandidate>(primitive.candidateIndex * sizeof(MeshletCandidate));
    Instance instance = getInstance(candidate.instanceId);
    MaterialData material = getMaterial(instance.materialIndex);
    if (material.albedoTextureIndex != 0xFFFFFFFF)
    {
        Texture2D<float4> albedo = ResourceDescriptorHeap[NonUniformResourceIndex(material.albedoTextureIndex)];
        SamplerState sampler = SamplerDescriptorHeap[g_Frame.linearRepeatSamplerIndex];
        float4 albedo_sample = albedo.Sample(sampler, vertex.uv);
        if (albedo_sample.a < 0.5)
        {
            discard;
        }
    }

    GBufferOutput Out;
    Out.GBuffer0 = float4(primitive.candidateIndex, primitive.primitiveId, 0.0f, 1.0f);
    Out.GBuffer1 = float4(0.0f, 1.0f, 0.0f, 1.0f);
    Out.GBuffer2 = float4(1.0f, 0.04f, 0.0f, 0.5f);

    return Out;
}