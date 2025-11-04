#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

void main(VertexAttribute vertex, PrimitiveAttribute primitive)
{
    ByteAddressBuffer visibleMeshletBuffer = ResourceDescriptorHeap[g_RasterizerParams.visibleMeshletsBufferIndex];
    MeshletCandidate2 candidate = visibleMeshletBuffer.Load<MeshletCandidate2>(primitive.candidateIndex * sizeof(MeshletCandidate));
    MaterialData material = getMaterial(candidate.materialIndex);
    SamplerState sampler = SamplerDescriptorHeap[g_Frame.linearRepeatSamplerIndex];

    float2 UV = vertex.uv * material.uvTilingOffset.xy;

    if (hasValidTexture(material.albedoTextureIndex))
    {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.albedoTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(sampler, UV);
        if (baseColorSample.a < 0.5)
        {
            discard;
        }
    }
}