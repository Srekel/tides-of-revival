#define DIRECT3D12
#define STAGE_FRAG

#define VL_PosNorTanUv0Col
#include "lit_gbuffer_resources.hlsli"
#include "utils.hlsli"

GBufferOutput PS_MAIN(VSOutput Input)
{
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[g_instanceRootConstants.materialBufferIndex];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(g_cam_pos.xyz - P);
    float2 UV = Input.UV * material.uvTilingOffset.xy;

    float3 baseColor = sRGBToLinear_Float3(material.baseColor.rgb);
    if (hasValidTexture(material.baseColorTextureIndex))
    {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(g_linear_repeat_sampler, UV);
        baseColor *= baseColorSample.rgb;
    }
    else
    {
        baseColor *= sRGBToLinear_Float3(Input.Color.rgb);
    }

    float3 N = normalize(Input.Normal.xyz);

    if (hasValidTexture(material.normalTextureIndex))
    {
        Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.normalTextureIndex)];

        float3x3 TBN = ComputeTBN(N, normalize(Input.Tangent));
        float3 tangentNormal = ReconstructNormal(SampleTex2D(normalTexture, g_linear_repeat_sampler, Input.UV), material.normalIntensity);
        N = normalize(mul(tangentNormal, TBN));
    }

    float roughness = material.roughness;
    float metallic = material.metallic;
    float occlusion = 1.0f;
    if (hasValidTexture(material.armTextureIndex))
    {
        Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.armTextureIndex)];
        float3 armSample = armTexture.Sample(g_linear_repeat_sampler, UV).rgb;
        occlusion = armSample.r;
        roughness = armSample.g;
        metallic = armSample.b;
    }

    // TODO: Provide this value from the material
    float reflectance = 0.5f;

    Out.GBuffer0 = float4(baseColor, 1.0f);
    Out.GBuffer1 = float4(N, 1.0f);
    Out.GBuffer2 = float4(occlusion, roughness, metallic, reflectance);

    RETURN(Out);
}
