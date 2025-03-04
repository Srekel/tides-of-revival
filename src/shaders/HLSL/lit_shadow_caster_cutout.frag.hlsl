#define DIRECT3D12
#define STAGE_FRAG

#define VL_PosNorTanUv0Col
#include "lit_shadow_caster_resources.hlsli"
#include "utils.hlsl"

void PS_MAIN(ShadowVSOutput Input, bool isFrontFace : SV_IsFrontFace)
{
    INIT_MAIN;

    ByteAddressBuffer instanceTransformsBuffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instanceTransformsBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[g_instanceRootConstants.materialBufferIndex];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    float2 UV = Input.UV * material.uvTilingOffset.xy;

    if (hasValidTexture(material.baseColorTextureIndex))
    {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(g_linear_repeat_sampler, UV);
        clip(baseColorSample.a - 0.5);
    }
}
