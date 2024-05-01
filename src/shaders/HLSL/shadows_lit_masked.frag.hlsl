#define DIRECT3D12
#define STAGE_FRAG

#include "shadows_lit_resources.hlsl"
#include "utils.hlsl"

void PS_MAIN( VSOutput Input, bool isFrontFace : SV_IsFrontFace ) {
    INIT_MAIN;

    ByteAddressBuffer instanceTransformsBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformsBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    InstanceMaterial material = materialsBuffer.Load<InstanceMaterial>(instance.materialBufferOffset);

    if (hasValidTexture(material.baseColorTextureIndex)) {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(Get(bilinearRepeatSampler), Input.UV);
        clip(baseColorSample.a - 0.5);
    }
}
