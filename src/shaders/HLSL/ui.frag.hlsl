#define DIRECT3D12
#define STAGE_FRAG

#include "ui_resources.hlsl"

float4 PS_MAIN(VSOutput input) : SV_Target
{
    INIT_MAIN;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_ui_transform_buffer_index];
    UITransform instance = instanceTransformBuffer.Load<UITransform>(input.InstanceID * sizeof(UITransform));

    Texture2D texture = ResourceDescriptorHeap[NonUniformResourceIndex(instance.textureIndex)];
    float4 color = texture.SampleLevel(g_linear_repeat_sampler, input.UV, 0);
    color.rgb *= color.a;
    color *= instance.color;
    RETURN(color);
}
