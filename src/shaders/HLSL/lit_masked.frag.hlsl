#define DIRECT3D12
#define STAGE_FRAG

#include "lit_resources.h"
#include "utils.h"

GBufferOutput PS_MAIN( VSOutput Input, bool isFrontFace : SV_IsFrontFace ) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformsBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformsBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    InstanceMaterial material = materialsBuffer.Load<InstanceMaterial>(instanceIndex * sizeof(InstanceMaterial));

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(Get(camPos).xyz - P);

    float3 baseColor = material.baseColor.rgb;
    if (hasValidTexture(material.baseColorTextureIndex)) {
        Texture2D baseColorTexture = ResourceDescriptorHeap[material.baseColorTextureIndex];
        float4 baseColorSample = baseColorTexture.Sample(Get(bilinearRepeatSampler), Input.UV);
        clip(baseColorSample.a - 0.5);
        baseColor *= baseColorSample.rgb;
    }

    float3 N = normalize(Input.Normal);
    if (hasValidTexture(material.normalTextureIndex)) {
        Texture2D normalTexture = ResourceDescriptorHeap[material.normalTextureIndex];
        N = UnpackNormals(Input.UV, V, normalTexture, Get(bilinearRepeatSampler), Input.Normal, 1.0f);
    }

    if (isFrontFace) {
        N *= -1.0;
    }

    float roughness = material.roughness;
    float metallic = material.metallic;
    if (hasValidTexture(material.armTextureIndex)) {
        Texture2D arm_texture = ResourceDescriptorHeap[material.armTextureIndex];
        float4 arm_sample = arm_texture.Sample(Get(bilinearRepeatSampler), Input.UV);
        roughness = arm_sample.g;
        metallic = arm_sample.b;
    }

    Out.GBuffer0 = float4(baseColor.rgb, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(1.0f, roughness, metallic, 1.0f);

    RETURN(Out);
}
