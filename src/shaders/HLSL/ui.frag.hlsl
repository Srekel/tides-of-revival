#define DIRECT3D12
#define STAGE_FRAG

#include "ui_resources.hlsli"
#include "utils.hlsli"

float4 PS_MAIN(VSOutput input) : SV_Target
{
    INIT_MAIN;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_ui_transform_buffer_index];
    UITransform instance = instanceTransformBuffer.Load<UITransform>(input.InstanceID * sizeof(UITransform));

    Texture2D texture = ResourceDescriptorHeap[NonUniformResourceIndex(instance.textureIndex)];
    float4 color = texture.SampleLevel(g_linear_repeat_sampler, input.UV, 0);
    color.a *= instance.color.a;
    color.rgb *= color.a;
    color.rgb *= sRGBToLinear_Float3(instance.color.rgb);

    color.rgb = LinearTosRGB_Float3(color.rgb);
    RETURN(color);
}
