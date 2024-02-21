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

    // Derive normals from the heightmap using the central differences method
    Texture2D heightmap = ResourceDescriptorHeap[Get(instance.heightmapTextureIndex)];

    // TODO(gmodarelli): Pass heightmap resolution in
    float2 e = float2(1.0f / 65.0f, 0.0);
    // TODO(gmodarelli): Pass terrainScale in
    float terrainScale = 500.0f;
    float l = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), saturate(Input.UV - e.xy), 0).r / terrainScale;
    float r = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), saturate(Input.UV + e.xy), 0).r / terrainScale;
    float b = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), saturate(Input.UV - e.yx), 0).r / terrainScale;
    float t = SampleLvlTex2D(heightmap, Get(bilinearClampSampler), saturate(Input.UV + e.yx), 0).r / terrainScale;
    float3 N = normalize(float3(l - r, 20.0 * e.x, b - t));

    // Recalculating the tangent now that the normal has been adjusted.
    float3 B = normalize(cross(N, Input.Tangent));
    float3 T = normalize(cross(N, B));
    float3x3 TBN = make_f3x3_rows(T, B, N);

    const float3 V = normalize(Get(camPos).xyz - P);

    Texture2D splatmap = ResourceDescriptorHeap[Get(instance.splatmapTextureIndex)];
    uint splatmapIndex = uint(SampleLvlTex2D(splatmap, Get(bilinearClampSampler), Input.UV, 0).r * 255);

    ByteAddressBuffer terrain_layers_buffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    TerrainLayerTextureIndices terrain_layers = terrain_layers_buffer.Load<TerrainLayerTextureIndices>(splatmapIndex * sizeof(TerrainLayerTextureIndices));
    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.diffuseIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.normalIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.armIndex)];

    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    float2 worldSpaceUV = Input.PositionWS.xz * 0.1f;
    float3 albedo = diffuseTexture.Sample(Get(bilinearRepeatSampler), worldSpaceUV).rgb;

    float4 sampleNormal = normalTexture.Sample(Get(bilinearRepeatSampler), worldSpaceUV);
    float3 tangentNormal = float3(0, 0, 0);
    tangentNormal.xy = sampleNormal.rg * 2.0 - 1.0;
    tangentNormal.z = sqrt(1.0 - saturate(dot(tangentNormal.xy, tangentNormal.xy)));
    N = normalize(mul(tangentNormal, TBN));

    float4 armSample = pow(armTexture.Sample(Get(bilinearRepeatSampler), worldSpaceUV), 1.0f / 2.2f);
    float roughness = armSample.g;
    float metallic = armSample.b;

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(armSample.rgb, 1.0f);

    RETURN(Out);
}
