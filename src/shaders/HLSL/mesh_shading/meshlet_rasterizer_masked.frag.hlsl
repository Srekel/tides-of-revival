#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

GBufferOutput main(VertexAttribute vertex, PrimitiveAttribute primitive)
{
    ByteAddressBuffer visible_meshlet_buffer = ResourceDescriptorHeap[g_rasterizer_params.visible_meshlets_buffer_index];
    MeshletCandidate candidate = visible_meshlet_buffer.Load<MeshletCandidate>(primitive.candidate_index * sizeof(MeshletCandidate));
    Instance instance = getInstance(candidate.instance_id);
    MaterialData material = getMaterial(instance.material_index);
    if (material.albedo_texture_index != 0xFFFFFFFF) {
        Texture2D<float4> albedo = ResourceDescriptorHeap[NonUniformResourceIndex(material.albedo_texture_index)];
        SamplerState sampler = SamplerDescriptorHeap[g_Frame.linear_repeat_sampler_index];
        float4 albedo_sample = albedo.Sample(sampler, vertex.uv);
        if (albedo_sample.a < 0.5) {
            discard;
        }
    }

    GBufferOutput Out;
    Out.GBuffer0 = float4(primitive.candidate_index, primitive.primitive_id, 0.0f, 1.0f);
    Out.GBuffer1 = float4(0.0f, 1.0f, 0.0f, 1.0f);
    Out.GBuffer2 = float4(1.0f, 0.04f, 0.0f, 0.5f);

    return Out;
}