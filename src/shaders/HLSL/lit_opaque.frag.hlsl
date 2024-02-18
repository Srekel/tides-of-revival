#define DIRECT3D12
#define STAGE_FRAG

#include "lit_resources.hlsl"
#include "utils.hlsl"

GBufferOutput PS_MAIN( VSOutput Input) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialBuffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    InstanceMaterial material = materialBuffer.Load<InstanceMaterial>(instanceIndex * sizeof(InstanceMaterial));

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(Get(camPos).xyz - P);

    float3 baseColor = material.baseColor.rgb;
    if (hasValidTexture(material.baseColorTextureIndex)) {
        Texture2D baseColorTexture = ResourceDescriptorHeap[material.baseColorTextureIndex];
        float4 baseColorSample = baseColorTexture.Sample(Get(bilinearRepeatSampler), Input.UV);
        baseColor *= baseColorSample.rgb;
    }

    float3 N = normalize(Input.Normal);
    if (hasValidTexture(material.normalTextureIndex)) {
        Texture2D normalTexture = ResourceDescriptorHeap[material.normalTextureIndex];
        N = UnpackNormals(Input.UV, V, normalTexture, Get(bilinearRepeatSampler), Input.Normal, 1.0f);
    }

    float roughness = material.roughness;
    float metallic = material.metallic;
    if (hasValidTexture(material.armTextureIndex)) {
        Texture2D armTexture = ResourceDescriptorHeap[material.armTextureIndex];
        float4 armSample = armTexture.Sample(Get(bilinearRepeatSampler), Input.UV);
        roughness = armSample.g;
        metallic = armSample.b;
    }

    Out.GBuffer0 = float4(baseColor.rgb, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(1.0f, roughness, metallic, 1.0f);

    RETURN(Out);
}
