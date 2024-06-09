#define DIRECT3D12
#define STAGE_FRAG

#define VL_PosNorTanUv0ColUV1
#include "tree_resources.hlsl"
#include "utils.hlsl"

GBufferOutput PS_MAIN( VSOutput Input, bool isFrontFace : SV_IsFrontFace ) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformsBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformsBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(Get(camPos).xyz - P);

    float3 baseColor = float3(0, 0, 0);
    if (hasValidTexture(material.baseColorTextureIndex)) {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(Get(bilinearRepeatSampler), Input.UV);
        clip(baseColorSample.a - 0.5);
        baseColor = baseColorSample.rgb;
    } else {
        baseColor = Input.Color.rgb;
    }
    baseColor = srgb_to_linear_float3(baseColor);

    float3 N = normalize(Input.Normal);
    if (hasValidTexture(material.normalTextureIndex)) {
        Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.normalTextureIndex)];
        N = UnpackNormals(Input.UV, -V, normalTexture, Get(bilinearRepeatSampler), Input.Normal, 1.0f);
    }

    // if (isFrontFace) {
    //     N *= -1.0;
    // }

    float roughness = material.roughness;
    float metallic = material.metallic;
    float occlusion = 1.0f;
    if (hasValidTexture(material.armTextureIndex)) {
        Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.armTextureIndex)];
        float3 armSample = armTexture.Sample(Get(bilinearRepeatSampler), Input.UV).rgb;
        occlusion = armSample.r;
        roughness = armSample.g;
        metallic = armSample.b;
    }

    if (material.detailFeature)
    {
        Texture2D detailMaskTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailMaskTextureIndex)];
        float detailMask = detailMaskTexture.Sample(Get(bilinearRepeatSampler), Input.UV).r;
        float2 detailUV = Input.UV;
        if (material.detailUseUV2)
        {
            detailUV = Input.UV1;
        }

        // Blend detail normal
        Texture2D detailNormalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailNormalTextureIndex)];
        float3 detailN = UnpackNormals(detailUV, -V, detailNormalTexture, Get(bilinearRepeatSampler), Input.Normal, 1.0f);
        N = lerp(N, detailN, detailMask);

        // Blend base color
        Texture2D detailBaseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailBaseColorTextureIndex)];
        float3 detailBaseColor = srgb_to_linear_float3(detailBaseColorTexture.Sample(Get(bilinearClampSampler), Input.UV).rgb);
        baseColor = lerp(baseColor, detailBaseColor, detailMask);

        // Blend ARM
        Texture2D detailArmTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.detailArmTextureIndex)];
        float3 detailArmSample = detailArmTexture.Sample(Get(bilinearRepeatSampler), Input.UV).rgb;
        occlusion = lerp(occlusion, detailArmSample.r, detailMask);
        roughness = lerp(roughness, detailArmSample.g, detailMask);
        metallic = lerp(metallic, detailArmSample.b, detailMask);
    }

    baseColor *= srgb_to_linear_float3(material.baseColor.rgb);

    Out.GBuffer0 = float4(baseColor.rgb, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(occlusion, roughness, metallic, 1.0f);

    RETURN(Out);
}
