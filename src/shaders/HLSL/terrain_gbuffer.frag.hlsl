#define DIRECT3D12
#define STAGE_FRAG

#include "terrain_gbuffer_resources.hlsli"
#include "utils.hlsl"

#define HEIGHBLEND_ENABLED 0
#define TRIPLANAR_ENABLED 0
#define TEXTURE_BOMBING_ENABLED 1

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

struct TriplanarUV
{
    float2 x;
    float2 y;
    float2 z;
};

TriplanarUV GetTriplanarUV(float3 P, float3 N)
{
    TriplanarUV triUV;
    triUV.x = P.zy;
    triUV.y = P.xz;
    triUV.z = P.xy;
    if (N.x < 0)
    {
        triUV.x.x = -triUV.x.x;
    }
    if (N.y < 0)
    {
        triUV.y.x = -triUV.y.x;
    }
    if (N.z >= 0)
    {
        triUV.z.x = -triUV.z.x;
    }
    return triUV;
}

float3 GetTriplanarWeights(float3 normalWS)
{
    float3 triplanar_weights = abs(normalWS);
    return triplanar_weights / (triplanar_weights.x + triplanar_weights.y + triplanar_weights.z + 0.00001);
}

float3 TriplanarSample(Texture2D texture, SamplerState samplerState, TriplanarUV uv, float3 weights)
{
    float3 xAxis = texture.Sample(samplerState, uv.x).rgb;
    float3 yAxis = texture.Sample(samplerState, uv.y).rgb;
    float3 zAxis = texture.Sample(samplerState, uv.z).rgb;

    return xAxis * weights.x + yAxis * weights.y + zAxis * weights.z;
}

float3 TriplanarSampleNormals(Texture2D texture, SamplerState samplerState, float3 N, TriplanarUV uv, float3 weights, float3x3 TBN)
{
    float3 tangentNormalX = ReconstructNormal(SampleTex2D(texture, samplerState, uv.x), 1.0f);
    float3 tangentNormalY = ReconstructNormal(SampleTex2D(texture, samplerState, uv.y), 1.0f);
    float3 tangentNormalZ = ReconstructNormal(SampleTex2D(texture, samplerState, uv.z), 1.0f);

    if (N.x < 0)
    {
        tangentNormalX.x = -tangentNormalX.x;
        tangentNormalX.z = -tangentNormalX.z;
    }
    if (N.y < 0)
    {
        tangentNormalY.x = -tangentNormalY.x;
        tangentNormalY.z = -tangentNormalY.z;
    }
    if (N.z >= 0)
    {
        tangentNormalZ.x = -tangentNormalZ.x;
    }
    else
    {
        tangentNormalZ.z = -tangentNormalZ.z;
    }

    tangentNormalX = mul(TBN, tangentNormalX);
    tangentNormalY = mul(TBN, tangentNormalY);
    tangentNormalZ = mul(TBN, tangentNormalZ);

    // float3 xAxis = UnpackNormals(uv.yz, -V, texture, samplerState, N, 1.0f);
    // float3 yAxis = UnpackNormals(uv.xz, -V, texture, samplerState, N, 1.0f);
    // float3 zAxis = UnpackNormals(uv.xy, -V, texture, samplerState, N, 1.0f);

    return normalize(tangentNormalX * weights.x + tangentNormalY * weights.y + tangentNormalY * weights.z);
}

// Breaking texture repetition
// https://www.shadertoy.com/view/lt2GDd
float4 hash4(float2 p) { return frac(sin(float4(1.0 + dot(p, float2(37.0, 17.0)),
                                                2.0 + dot(p, float2(11.0, 47.0)),
                                                3.0 + dot(p, float2(41.0, 29.0)),
                                                4.0 + dot(p, float2(23.0, 31.0)))) *
                                     103.0); }

float4 SampleNoTiling(Texture2D tex, SamplerState ss, float2 uv)
{
    float2 iuv = floor(uv);
    float2 fuv = frac(uv);

    // generate per-tile transform
    float4 ofa = hash4(iuv + float2(0.0, 0.0));
    float4 ofb = hash4(iuv + float2(1.0, 0.0));
    float4 ofc = hash4(iuv + float2(0.0, 1.0));
    float4 ofd = hash4(iuv + float2(1.0, 1.0));

    float2 _ddx = ddx(uv);
    float2 _ddy = ddy(uv);

    // transform per-tile uvs
    ofa.zw = sign(ofa.zw - 0.5);
    ofb.zw = sign(ofb.zw - 0.5);
    ofc.zw = sign(ofc.zw - 0.5);
    ofd.zw = sign(ofd.zw - 0.5);

    // uv's, and derivarives (for correct mipmapping)
    float2 uva = uv * ofa.zw + ofa.xy;
    float2 _ddxa = _ddx * ofa.zw;
    float2 _ddya = _ddy * ofa.zw;
    float2 uvb = uv * ofb.zw + ofb.xy;
    float2 _ddxb = _ddx * ofb.zw;
    float2 _ddyb = _ddy * ofb.zw;
    float2 uvc = uv * ofc.zw + ofc.xy;
    float2 _ddxc = _ddx * ofc.zw;
    float2 _ddyc = _ddy * ofc.zw;
    float2 uvd = uv * ofd.zw + ofd.xy;
    float2 _ddxd = _ddx * ofd.zw;
    float2 _ddyd = _ddy * ofd.zw;

    // fetch and blend
    float2 b = smoothstep(0.25, 0.75, fuv);

    return lerp(lerp(tex.SampleGrad(ss, uva, _ddxa, _ddya),
                     tex.SampleGrad(ss, uvb, _ddxb, _ddyb), b.x),
                lerp(tex.SampleGrad(ss, uvc, _ddxc, _ddyc),
                     tex.SampleGrad(ss, uvd, _ddxd, _ddyd), b.x),
                b.y);
}

// Terrain Layer sampling
// ======================
void SampleTerrainLayer(uint layer_index, float3 triplanarWeights, float3 P, float3 N, float3x3 TBN, out float3 albedo, out float3 normal, out float3 arm, out float height)
{
    SamplerState samplerState = g_linear_repeat_sampler;
    TerrainLayerTextureIndices terrain_layer = g_layers[layer_index];

    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.diffuseIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.armIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.normalIndex)];

#if TRIPLANAR_ENABLED
    TriplanarUV uv = GetTriplanarUV(P, N);
    albedo = TriplanarSample(diffuseTexture, samplerState, uv, triplanarWeights);
    arm = TriplanarSample(armTexture, samplerState, uv, triplanarWeights);
    normal = TriplanarSampleNormals(normalTexture, samplerState, N, uv, triplanarWeights, TBN);
#else

#if TEXTURE_BOMBING_ENABLED
    float2 uv = P.xz;
    albedo = SampleNoTiling(diffuseTexture, samplerState, uv).rgb;
    arm = SampleNoTiling(armTexture, samplerState, uv).rgb;
    // arm.g = 0.9f;
    normal = ReconstructNormal(SampleNoTiling(normalTexture, samplerState, uv), 1.0f);
    normal = mul(TBN, normal);
#else
    float2 uv = P.xz;
    albedo = diffuseTexture.Sample(samplerState, uv).rgb;
    arm = armTexture.Sample(samplerState, uv).rgb;
    // arm.g = 0.9f;
    normal = ReconstructNormal(normalTexture.Sample(samplerState, uv), 1.0f);
    normal = mul(TBN, normal);
#endif

#endif

#if HEIGHBLEND_ENABLED
    Texture2D heightTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.heightIndex)];
    height = TriplanarSample(heightTexture, samplerState, uv, triplanarWeights).r;
#else
    height = 0;
#endif
}

// TODO(gmodarelli): These distances and scales could be set per layer
float GetCoordScaleByDistance(float3 positionWS, float3 cameraPosition)
{
    float d = distance(positionWS, cameraPosition);

    if (d < 20.0f)
    {
        return 1.0f;
    }
    else if (d < 100.0f)
    {
        return 0.5f;
    }
    else if (d < 200.0f)
    {
        return 0.05f;
    }

    return 0.005f;
}

GBufferOutput PS_MAIN(TerrainVSOutput Input, float3 barycentrics : SV_Barycentrics)
{
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    TerrainInstanceData instance = instanceTransformBuffer.Load<TerrainInstanceData>(instanceIndex * sizeof(TerrainInstanceData));

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(g_cam_pos.xyz - P);

    // Generate TBN for sampling layers' normal maps
    // =============================================
    Texture2D normalmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.normalmapTextureIndex)];
    float3 normalWS = normalize(normalmap.SampleLevel(g_linear_repeat_sampler, Input.UV, 0).rgb * 2.0 - 1.0);
    normalWS = mul((float3x3)instance.worldMat, normalWS);
    float3 tangentWS = cross(instance.worldMat._13_23_33, normalWS);
    float3 bitangentWS = cross(normalWS, tangentWS);
    float3x3 TBN = float3x3(-tangentWS, bitangentWS, normalWS);

    float slope = dot(normalWS, float3(0, 1, 0));
    slope = smoothstep(g_black_point, g_white_point, slope);

    uint grass_layer_index = 1;
    uint rock_layer_index = 2;

    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    // TODO(gmodarelli): Use more UV techniques to break tiling patterns
    float3 worldSpaceUV = Input.PositionWS.xyz * GetCoordScaleByDistance(P, g_cam_pos.xyz);
    float3 triplanarWeights = GetTriplanarWeights(normalWS);

    float3 grass_albedo;
    float3 grass_normal;
    float3 grass_arm;
    float grass_height;
    SampleTerrainLayer(grass_layer_index, triplanarWeights, worldSpaceUV, normalWS, TBN, grass_albedo, grass_normal, grass_arm, grass_height);

    float3 rock_albedo;
    float3 rock_normal;
    float3 rock_arm;
    float rock_height;
    SampleTerrainLayer(rock_layer_index, triplanarWeights, worldSpaceUV, normalWS, TBN, rock_albedo, rock_normal, rock_arm, rock_height);

#if HEIGHBLEND_ENABLED
    float b1, b2;
    CalculateBlendingFactors(grass_height, rock_height, slope, 1.0f - slope, b1, b2);
    float3 albedo = HeightBlend(grass_albedo.rgb, rock_albedo.rgb, b1, b2);
    normalWS = normalize(HeightBlend(grass_normal, rock_normal, b1, b2));
    float3 arm = HeightBlend(grass_arm, rock_arm, b1, b2);
#else
    float3 albedo = lerp(rock_albedo, grass_albedo, slope);
    normalWS = lerp(rock_normal, grass_normal, slope);
    float3 arm = lerp(rock_arm, grass_arm, slope);
#endif

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(normalWS, 1.0f);
    Out.GBuffer2 = float4(arm, 1.0f);

    RETURN(Out);
}
