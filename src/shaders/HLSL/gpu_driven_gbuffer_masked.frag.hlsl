#define DIRECT3D12
#define STAGE_FRAG

#include "gpu_driven_gbuffer_resources.hlsli"
#include "material.hlsli"
#include "utils.hlsli"

GBufferOutput PS_MAIN(VSOutput Input)
{
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceIndirectionBuffer = ResourceDescriptorHeap[g_InstanceIndirectionBufferIndex];
    InstanceIndirectionData instanceIndirection = instanceIndirectionBuffer.Load<InstanceIndirectionData>(Input.InstanceID * sizeof(InstanceIndirectionData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[g_MaterialBufferIndex];
    MaterialData material = materialsBuffer.Load<MaterialData>(instanceIndirection.materialIndex);

    float2 UV = Input.UV * material.uvTilingOffset.xy;

    float3 baseColor = sRGBToLinear_Float3(material.baseColor.rgb);
    if (hasValidTexture(material.baseColorTextureIndex))
    {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(g_linear_repeat_sampler, UV);
        clip(baseColorSample.a - 0.5);
        baseColor *= baseColorSample.rgb;
    }

    Out.GBuffer0 = float4(baseColor, 1.0f);
    Out.GBuffer1 = float4(normalize(Input.Normal), 1.0f);
    Out.GBuffer2 = float4(1.0f, material.roughness, material.metallic, 0.5f);

    RETURN(Out);
}
