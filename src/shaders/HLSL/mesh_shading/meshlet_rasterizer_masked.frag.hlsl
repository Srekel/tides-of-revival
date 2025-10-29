#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "../FastNoiseLite.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

GBufferOutput main(VertexAttribute vertex, PrimitiveAttribute primitive)
{
    ByteAddressBuffer visibleMeshletBuffer = ResourceDescriptorHeap[g_RasterizerParams.visibleMeshletsBufferIndex];
    MeshletCandidate candidate = visibleMeshletBuffer.Load<MeshletCandidate>(primitive.candidateIndex * sizeof(MeshletCandidate));
    Instance instance = getInstance(candidate.instanceId);
    MaterialData material = getMaterial(instance.materialIndex);
    SamplerState sampler = SamplerDescriptorHeap[g_Frame.linearRepeatSamplerIndex];

    const float3 P = vertex.positionWS;
    const float3 V = normalize(g_Frame.cameraPosition.xyz - P);
    float2 UV = vertex.uv * material.uvTilingOffset.xy;

    float3 baseColor = sRGBToLinear_Float3(material.albedoColor.rgb);
    if (hasValidTexture(material.albedoTextureIndex))
    {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.albedoTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(sampler, UV);
        if (baseColorSample.a < 0.5)
        {
            discard;
        }

        baseColor *= baseColorSample.rgb;
    }
    else
    {
        baseColor *= sRGBToLinear_Float3(vertex.color.rgb);
    }

    if (material.randomColorFeatureEnabled)
    {
        if (hasValidTexture(material.randomColorGradientTextureIndex))
        {
            // TODO(gmodarelli): Use custom seed, default 1337
            fnl_state randomState = fnlCreateState();
            randomState.frequency = material.randomColorNoiseScale;
            float noise = fnlGetNoise3D(randomState, vertex.pivotWS.x, vertex.pivotWS.y, vertex.pivotWS.z) * 0.5 + 0.5;
            Texture2D gradientTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.randomColorGradientTextureIndex)];
            float4 gradientSample = gradientTexture.Sample(sampler, float2(noise, 0.5));
            baseColor = BlendDodge(float4(baseColor, 1.0), gradientSample, 1.0).rgb;
        }
    }

    float3 N = normalize(vertex.normal);

    if (hasValidTexture(material.normalTextureIndex))
    {
        Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.normalTextureIndex)];

        float3x3 TBN = ComputeTBN(N, normalize(vertex.tangent));
        float3 tangentNormal = ReconstructNormal(SampleTex2D(normalTexture, sampler, UV), material.normalIntensity);
        N = normalize(mul(tangentNormal, TBN));
    }

    float roughness = material.roughness;
    float metallic = material.metallic;
    float occlusion = 1.0f;
    if (hasValidTexture(material.armTextureIndex))
    {
        Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.armTextureIndex)];
        float3 armSample = armTexture.Sample(sampler, UV).rgb;
        occlusion = armSample.r;
        roughness = armSample.g;
        metallic = armSample.b;
    }

    // TODO: Provide this value from the material
    float reflectance = 0.5f;

    GBufferOutput Out;
    Out.GBuffer0 = float4(baseColor, 1.0f);
    Out.GBuffer1 = float4(N, 1.0f);
    Out.GBuffer2 = float4(occlusion, roughness, metallic, reflectance);

    return Out;
}