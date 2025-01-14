#define DIRECT3D12
#define STAGE_FRAG

#define VL_PosNorTanUv0Col
#include "lit_resources.hlsl"
#include "utils.hlsl"

GBufferOutput PS_MAIN( VSOutput Input) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_instance_data_buffer_index];
    uint instanceIndex = Input.InstanceID + g_start_instance_location;
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    ByteAddressBuffer materialsBuffer = ResourceDescriptorHeap[g_material_buffer_index];
    MaterialData material = materialsBuffer.Load<MaterialData>(instance.materialBufferOffset);

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(g_cam_pos.xyz - P);

    float3 baseColor = sRGBToLinear_Float3(material.baseColor.rgb);
    if (hasValidTexture(material.baseColorTextureIndex)) {
        Texture2D baseColorTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.baseColorTextureIndex)];
        float4 baseColorSample = baseColorTexture.Sample(g_linear_repeat_sampler, Input.UV);
        baseColor *= baseColorSample.rgb;
    } else {
        baseColor *= sRGBToLinear_Float3(Input.Color.rgb);
    }

    float3 N = normalize(Input.Normal);
    if (hasValidTexture(material.normalTextureIndex)) {
        float3x3 TBN = ComputeTBN(Input.Normal, Input.Tangent);
        Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.normalTextureIndex)];
        float3 tangentNormal = ReconstructNormal(SampleTex2D(normalTexture, g_linear_repeat_sampler, Input.UV), 1.0f);
        N = normalize(mul(tangentNormal, TBN));
    }

    float roughness = material.roughness;
    float metallic = material.metallic;
    float occlusion = 1.0f;
    if (hasValidTexture(material.armTextureIndex)) {
        Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(material.armTextureIndex)];
        float3 armSample = armTexture.Sample(g_linear_repeat_sampler, Input.UV).rgb;
        occlusion = armSample.r;
        roughness = armSample.g;
        metallic = armSample.b;
    }

    Out.GBuffer0 = float4(baseColor, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(occlusion, roughness, metallic, 1.0f);

    RETURN(Out);
}
