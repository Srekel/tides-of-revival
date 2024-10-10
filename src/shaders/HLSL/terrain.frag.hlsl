#define DIRECT3D12
#define STAGE_FRAG

#include "terrain_resources.hlsl"
#include "utils.hlsl"

void SampleTerrainLayer(uint layer_index, float2 uv, float3 N, float3 V, out float3 albedo, out float3 normal, out float3 arm) {
    ByteAddressBuffer terrain_layers_buffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    TerrainLayerTextureIndices terrain_layers = terrain_layers_buffer.Load<TerrainLayerTextureIndices>(layer_index * sizeof(TerrainLayerTextureIndices));

    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.diffuseIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.normalIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.armIndex)];

    albedo = diffuseTexture.Sample(Get(bilinearRepeatSampler), uv).rgb;
    normal = UnpackNormals(uv, -V, normalTexture, Get(bilinearRepeatSampler), N, 1.0f);
    arm = armTexture.Sample(Get(bilinearRepeatSampler), uv).rgb;
}

GBufferOutput PS_MAIN( VSOutput Input ) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    const float3 P = Input.PositionWS.xyz;

    float3 N = normalize(Input.Normal);
    float slope = dot(N, float3(0, 1, 0));
    slope = smoothstep(0.9, 1.0, slope);
    const float3 V = normalize(Get(camPos).xyz - P);

    uint grass_layer_index = 1;
    uint rock_layer_index = 2;

    float3 grass_albedo;
    float3 grass_normal;
    float3 grass_arm;

    float3 rock_albedo;
    float3 rock_normal;
    float3 rock_arm;

    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    float2 worldSpaceUV = Input.PositionWS.xz * 0.1f;
    SampleTerrainLayer(grass_layer_index, worldSpaceUV, N, V, grass_albedo, grass_normal, grass_arm);
    SampleTerrainLayer(rock_layer_index, worldSpaceUV, N, V, rock_albedo, rock_normal, rock_arm);

    float3 albedo = lerp(rock_albedo, grass_albedo, slope);
    N = lerp(rock_normal, grass_normal, slope);
    float3 arm = lerp(rock_arm, grass_arm, slope);

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(arm, 1.0f);

    RETURN(Out);
}
