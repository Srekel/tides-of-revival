#define DIRECT3D12
#define STAGE_FRAG

#define VL_PosNorTanUv0ColUV1
#include "tree_gbuffer_resources.hlsli"
#include "utils.hlsl"

GBufferOutput PS_MAIN(VSOutput Input)
{
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[g_instanceRootConstants.materialBufferIndex];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(g_cam_pos.xyz - P);

    float3 baseColor = float3(0, 0, 0);
    if (hasValidTexture(material.baseColorTextureIndex))
    {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(g_linear_repeat_sampler, Input.UV);
        baseColor = baseColorSample.rgb;
    }
    else
    {
        baseColor = sRGBToLinear_Float3(Input.Color.rgb);
    }

    float3 N = normalize(Input.Normal);
    float3x3 TBN = ComputeTBN(Input.Normal, Input.Tangent);
    if (hasValidTexture(material.normalTextureIndex))
    {
        Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.normalTextureIndex)];
        float3 tangentNormal = ReconstructNormal(SampleTex2D(normalTexture, g_linear_repeat_sampler, Input.UV), 1.0f);
        N = normalize(mul(tangentNormal, TBN));
    }

    float roughness = material.roughness;
    float metallic = material.metallic;
    float occlusion = 1.0f;
    if (hasValidTexture(material.armTextureIndex))
    {
        Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.armTextureIndex)];
        float3 armSample = armTexture.Sample(g_linear_repeat_sampler, Input.UV).rgb;
        occlusion = armSample.r;
        roughness = armSample.g;
        metallic = armSample.b;
    }

    if (material.detailFeature)
    {
        Texture2D detailMaskTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailMaskTextureIndex)];
        float detailMask = detailMaskTexture.Sample(g_linear_repeat_sampler, Input.UV).r;
        float2 detailUV = Input.UV;
        if (material.detailUseUV2)
        {
            detailUV = Input.UV1;
        }

        // Blend detail normal
        Texture2D detailNormalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailNormalTextureIndex)];
        float3 tangentNormal = ReconstructNormal(SampleTex2D(detailNormalTexture, g_linear_repeat_sampler, detailUV), 1.0f);
        float3 detailN = normalize(mul(tangentNormal, TBN));
        N = lerp(N, detailN, detailMask);

        // Blend base color
        Texture2D detailBaseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailBaseColorTextureIndex)];
        float3 detailBaseColor = detailBaseColorTexture.Sample(g_linear_clamp_edge_sampler, detailUV).rgb;
        baseColor = lerp(baseColor, detailBaseColor, detailMask);

        // Blend ARM
        Texture2D detailArmTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailArmTextureIndex)];
        float3 detailArmSample = detailArmTexture.Sample(g_linear_repeat_sampler, detailUV).rgb;
        occlusion = lerp(occlusion, detailArmSample.r, detailMask);
        roughness = lerp(roughness, detailArmSample.g, detailMask);
        metallic = lerp(metallic, detailArmSample.b, detailMask);
    }

    baseColor *= sRGBToLinear_Float3(material.baseColor.rgb);

    // TODO: Provide this value from the material
    float reflectance = 0.5f;

    Out.GBuffer0 = float4(baseColor.rgb, 1.0f);
    Out.GBuffer1 = float4(N, 1.0f);
    Out.GBuffer2 = float4(occlusion, roughness, metallic, reflectance);

    RETURN(Out);
}
