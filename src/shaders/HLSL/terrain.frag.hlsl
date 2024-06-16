#define DIRECT3D12
#define STAGE_FRAG

#include "terrain_resources.hlsl"
#include "utils.hlsl"

GBufferOutput PS_MAIN( VSOutput Input ) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    const float3 P = Input.PositionWS.xyz;

    float3 N = normalize(Input.Normal);
    const float3 V = normalize(Get(camPos).xyz - P);

    Texture2D splatmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.splatmapTextureIndex)];
    uint splatmapIndex = uint(SampleLvlTex2D(splatmap, Get(bilinearClampSampler), Input.UV, 0).r * 255);

    ByteAddressBuffer terrain_layers_buffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    TerrainLayerTextureIndices terrain_layers = terrain_layers_buffer.Load<TerrainLayerTextureIndices>(splatmapIndex * sizeof(TerrainLayerTextureIndices));
    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.diffuseIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.normalIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.armIndex)];

    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    float2 worldSpaceUV = Input.PositionWS.xz * 0.1f;
    float3 albedo = diffuseTexture.Sample(Get(bilinearRepeatSampler), worldSpaceUV).rgb;
    N = UnpackNormals(worldSpaceUV, -V, normalTexture, Get(bilinearRepeatSampler), N, 1.0f);

    float3 armSample = armTexture.Sample(Get(bilinearRepeatSampler), worldSpaceUV).rgb;
    float roughness = armSample.g;
    float metallic = armSample.b;

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(armSample.rgb, 1.0f);

    RETURN(Out);
}
