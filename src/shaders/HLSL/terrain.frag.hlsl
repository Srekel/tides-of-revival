#define DIRECT3D12
#define STAGE_FRAG

#include "terrain_resources.hlsl"
#include "utils.hlsl"

// Height-based blending
// =====================
void CalculateBlendingFactors(float height1, float height2, float a1, float a2, out float b1, out float b2)
{
    float depth = 0.2f;
    float ma = max(height1 + a1, height2 + a2) - depth;

    b1 = max(height1 + a1 - ma, 0.0f);
    b2 = max(height2 + a2 - ma, 0.0f);
}

float3 HeightBlend(float3 sample1, float3 sample2, float b1, float b2)
{
    return (sample1 * b1 + sample2 * b2) / (b1 + b2);
}

// Triplanar Sampling
// ==================
float3 GetTriplanarWeights(float3 normal)
{
    float3 blending = abs(normal);
    blending = normalize(max(blending, 0.00001));
    float b = blending.x + blending.y + blending.z;
    return blending / b;
}

float3 TriplanarSample(Texture2D texture, SamplerState samplerState, float3 uv, float3 weights)
{
    float3 xAxis = texture.Sample(samplerState, uv.yz).rgb;
    float3 yAxis = texture.Sample(samplerState, uv.xz).rgb;
    float3 zAxis = texture.Sample(samplerState, uv.xy).rgb;

    return xAxis * weights.x + yAxis * weights.y + zAxis * weights.z;
}

float3 TriplanarSampleNormals(Texture2D texture, SamplerState samplerState, float3 uv, float3 N, float3 V, float3 weights)
{
    float3 xAxis = UnpackNormals(uv.yz, -V, texture, samplerState, N, 1.0f);
    float3 yAxis = UnpackNormals(uv.xz, -V, texture, samplerState, N, 1.0f);
    float3 zAxis = UnpackNormals(uv.xy, -V, texture, samplerState, N, 1.0f);

    return xAxis * weights.x + yAxis * weights.y + zAxis * weights.z;
}

// Terrain Layer sampling
// ======================
void SampleTerrainLayer(uint layer_index, float3 triplanarWeights, float3 P, float3 N, float3 V, out float3 albedo, out float3 normal, out float3 arm, out float height)
{
    ByteAddressBuffer terrain_layers_buffer = ResourceDescriptorHeap[Get(materialBufferIndex)];
    TerrainLayerTextureIndices terrain_layers = terrain_layers_buffer.Load<TerrainLayerTextureIndices>(layer_index * sizeof(TerrainLayerTextureIndices));

    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.diffuseIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.armIndex)];
    Texture2D heightTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.heightIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.normalIndex)];
    SamplerState samplerState = Get(g_linear_repeat_sampler);

    if (Get(triplanarMapping))
    {
        albedo = TriplanarSample(diffuseTexture, samplerState, P, triplanarWeights);
        arm = TriplanarSample(armTexture, samplerState, P, triplanarWeights);
        height = TriplanarSample(heightTexture, samplerState, P, triplanarWeights).r;
        normal = TriplanarSampleNormals(normalTexture, samplerState, P, N, -V, triplanarWeights);
    }
    else
    {
        albedo = diffuseTexture.Sample(samplerState, P.yz).rgb;
        arm = armTexture.Sample(samplerState, P.yz).rgb;
        height = heightTexture.Sample(samplerState, P.yz).r;
        normal = UnpackNormals(P.xz, -V, normalTexture, samplerState, N, 1.0f);
    }
}

GBufferOutput PS_MAIN( VSOutput Input, float3 barycentrics : SV_Barycentrics ) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[Get(instanceDataBufferIndex)];
    uint instanceIndex = Input.InstanceID + Get(startInstanceLocation);
    InstanceData instance = instanceTransformBuffer.Load<InstanceData>(instanceIndex * sizeof(InstanceData));

    const float3 P = Input.PositionWS.xyz;

    float3 N = normalize(Input.Normal);
    float slope = dot(N, float3(0, 1, 0));
    slope = smoothstep(Get(blackPoint), Get(whitePoint), slope);
    const float3 V = normalize(Get(camPos).xyz - P);

    uint grass_layer_index = 1;
    uint rock_layer_index = 2;

    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    // TODO(gmodarelli): Scale UVs based on distance from camera
    // TODO(gmodarelli): Use more UV techniques to break tiling patterns
    float3 worldSpaceUV = Input.PositionWS.xyz * 1.0f;
    float3 triplanarWeights = GetTriplanarWeights(N);

    float3 grass_albedo;
    float3 grass_normal;
    float3 grass_arm;
    float grass_height;
    SampleTerrainLayer(grass_layer_index, triplanarWeights, worldSpaceUV, N, V, grass_albedo, grass_normal, grass_arm, grass_height);

    float3 rock_albedo;
    float3 rock_normal;
    float3 rock_arm;
    float rock_height;
    SampleTerrainLayer(rock_layer_index, triplanarWeights, worldSpaceUV * 0.1f, N, V, rock_albedo, rock_normal, rock_arm, rock_height);

#if 0
    float3 albedo = lerp(rock_albedo, grass_albedo, slope);
    N = lerp(rock_normal, grass_normal, slope);
    float3 arm = lerp(rock_arm, grass_arm, slope);
#else
    float b1, b2;
    CalculateBlendingFactors(grass_height, rock_height, slope, 1.0f - slope, b1, b2);
    float3 albedo = HeightBlend(grass_albedo.rgb, rock_albedo.rgb, b1, b2);
    N = normalize(HeightBlend(grass_normal, rock_normal, b1, b2));
    float3 arm = HeightBlend(grass_arm, rock_arm, b1, b2);
#endif

    // const float3 lod_colors[4] = {
    //     float3(1, 0, 0),
    //     float3(0, 1, 0),
    //     float3(0, 0, 1),
    //     float3(0, 1, 1)
    // };

    // Out.GBuffer0 = float4(lod_colors[instance.lod], 1.0f);

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(N * 0.5f + 0.5f, 1.0f);
    Out.GBuffer2 = float4(arm, 1.0f);

    RETURN(Out);
}
