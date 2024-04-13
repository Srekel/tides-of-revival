#define DIRECT3D12
#define STAGE_FRAG

#include "ui_resources.hlsl"

float4 PS_MAIN(VSOutput input) : SV_Target
{
    INIT_MAIN;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[Get(uiTransformBufferIndex)];
    UITransform instance = instanceTransformBuffer.Load<UITransform>(input.InstanceID * sizeof(UITransform));

    Texture2D texture = ResourceDescriptorHeap[NonUniformResourceIndex(instance.textureIndex)];
    float4 color = texture.SampleLevel(Get(bilinearRepeatSampler), input.UV, 0);
    color *= instance.color;
    RETURN(color);
}
