#define DIRECT3D12
#define STAGE_FRAG

#define VL_PosNorTanUv0ColUV1
#include "shadows_tree_resources.hlsl"
#include "utils.hlsl"

void PS_MAIN( VSOutput Input) {
    INIT_MAIN;

    ByteAddressBuffer instanceTransformsBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformsBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    if (hasValidTexture(material.baseColorTextureIndex)) {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(Get(g_linear_repeat_sampler), Input.UV);
        clip(baseColorSample.a - 0.5);
    }
}
