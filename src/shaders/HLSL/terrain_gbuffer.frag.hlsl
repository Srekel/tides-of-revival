#define DIRECT3D12
#define STAGE_FRAG

#include "terrain_gbuffer_resources.hlsli"
#include "utils.hlsl"

#define TRIPLANAR_ENABLED 1
#define TEXTURE_BOMBING_ENABLED 1

// Texture bombing
// ===============
// https://www.shadertoy.com/view/lt2GDd
float4 hash4(float2 p) { return frac(sin(float4(1.0 + dot(p, float2(37.0, 17.0)),
                                                2.0 + dot(p, float2(11.0, 47.0)),
                                                3.0 + dot(p, float2(41.0, 29.0)),
                                                4.0 + dot(p, float2(23.0, 31.0)))) *
                                     103.0); }

float4 SampleTextureBombing(Texture2D tex, SamplerState ss, float2 uv)
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
// =================
float3 TriplanarSample(Texture2D texture, SamplerState samplerState, float3 positionWS, float3 normalWS)
{
#if TEXTURE_BOMBING_ENABLED
    float3 dx = SampleTextureBombing(texture, samplerState, positionWS.zy).rgb;
    float3 dy = SampleTextureBombing(texture, samplerState, positionWS.xz).rgb;
    float3 dz = SampleTextureBombing(texture, samplerState, positionWS.xy).rgb;
#else
    float3 dx = texture.Sample(samplerState, positionWS.zy).rgb;
    float3 dy = texture.Sample(samplerState, positionWS.xz).rgb;
    float3 dz = texture.Sample(samplerState, positionWS.xy).rgb;
#endif

    float3 weights = abs(normalWS);
    weights = weights / (weights.x + weights.y + weights.z);

    return dx * weights.x + dy * weights.y + dz * weights.z;
}

float3 TriplanarSampleNormals(Texture2D texture, SamplerState samplerState, float3 positionWS, float3 normalWS, float triplanarScale)
{
    float2 uvx = positionWS.zy;
    float2 uvy = positionWS.xz;
    float2 uvz = positionWS.xy;

#if TEXTURE_BOMBING_ENABLED
    float3 tx = ReconstructNormal(SampleTextureBombing(texture, samplerState, uvx * triplanarScale), 1.0f);
    float3 ty = ReconstructNormal(SampleTextureBombing(texture, samplerState, uvy * triplanarScale), 1.0f);
    float3 tz = ReconstructNormal(SampleTextureBombing(texture, samplerState, uvz * triplanarScale), 1.0f);
#else
    float3 tx = ReconstructNormal(texture.Sample(samplerState, uvx * triplanarScale), 1.0f);
    float3 ty = ReconstructNormal(texture.Sample(samplerState, uvy * triplanarScale), 1.0f);
    float3 tz = ReconstructNormal(texture.Sample(samplerState, uvz * triplanarScale), 1.0f);
#endif

    float3 weights = abs(normalWS);
    weights = weights / (weights.x + weights.y + weights.z);

    float3 axis = sign(normalWS);

    float3 tangentX = normalize(cross(normalWS, float3(0.0f, -axis.x, 0.0f)));
    float3 bitangentX = normalize(cross(tangentX, normalWS)) * axis.x;
    float3x3 tbnX = float3x3(tangentX, bitangentX, normalWS);

    float3 tangentY = normalize(cross(normalWS, float3(0.0f, 0.0f, axis.y)));
    float3 bitangentY = normalize(cross(tangentY, normalWS)) * axis.y;
    float3x3 tbnY = float3x3(tangentY, bitangentY, normalWS);

    float3 tangentZ = normalize(cross(normalWS, float3(axis.z, 0.0f, 0.0f)));
    float3 bitangentZ = normalize(cross(tangentZ, normalWS)) * axis.z;
    float3x3 tbnZ = float3x3(tangentZ, bitangentZ, normalWS);

    return normalize(
        clamp(mul(tbnX, tx), -1.0f, 1.0f) * weights.x +
        clamp(mul(tbnY, ty), -1.0f, 1.0f) * weights.y +
        clamp(mul(tbnZ, tz), -1.0f, 1.0f) * weights.z);
}

// Terrain Layer sampling
// ======================
void SampleTerrainLayer(uint layer_index, float3 P, float3 N, float triplanarScale, out float3 albedo, out float3 normal, out float3 arm, out float height)
{
    SamplerState samplerState = g_linear_repeat_sampler;
    TerrainLayerTextureIndices terrain_layer = g_layers[layer_index];

    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.diffuseIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.armIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.normalIndex)];
    Texture2D heightTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.heightIndex)];

#if TRIPLANAR_ENABLED
    albedo = TriplanarSample(diffuseTexture, samplerState, P * triplanarScale, N);
    arm = TriplanarSample(armTexture, samplerState, P * triplanarScale, N);
    height = TriplanarSample(heightTexture, samplerState, P * triplanarScale, N).r;
    normal = TriplanarSampleNormals(normalTexture, samplerState, P, N, triplanarScale);
#else
    float2 uv = P.xz * triplanarScale;
    albedo = diffuseTexture.Sample(samplerState, uv).rgb;
    arm = armTexture.Sample(samplerState, uv).rgb;
    height = heightTexture.Sample(samplerState, uv).r;
    normal = ReconstructNormal(normalTexture.Sample(samplerState, uv), 1.0f);
    float3 axis = sign(N);
    float3 tangent = normalize(cross(N, float3(0.0f, 0.0f, axis.y)));
    float3 bitangent = normalize(cross(tangent, N)) * axis.y;
    float3x3 TBN = float3x3(tangent, bitangent, N);
    normal = clamp(mul(TBN, normal), -1.0f, 1.0f);
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

    Texture2D normalmap = ResourceDescriptorHeap[NonUniformResourceIndex(instance.normalmapTextureIndex)];
    float3 normalWS = normalize(normalmap.SampleLevel(g_linear_repeat_sampler, Input.UV, 0).rgb * 2.0 - 1.0);
    normalWS = mul((float3x3)instance.worldMat, normalWS);

    float slope = dot(normalWS, float3(0, 1, 0));
    slope = smoothstep(g_black_point, g_white_point, slope);

    uint grass_layer_index = 1;
    uint rock_layer_index = 2;

    float triplanarScale = GetCoordScaleByDistance(P, g_cam_pos.xyz);
    float3 worldSpaceUV = Input.PositionWS.xyz * GetCoordScaleByDistance(P, g_cam_pos.xyz);

    float3 grass_albedo;
    float3 grass_normal;
    float3 grass_arm;
    float grass_height;
    SampleTerrainLayer(grass_layer_index, Input.PositionWS.xyz, normalWS, triplanarScale, grass_albedo, grass_normal, grass_arm, grass_height);

    float3 rock_albedo;
    float3 rock_normal;
    float3 rock_arm;
    float rock_height;
    SampleTerrainLayer(rock_layer_index, Input.PositionWS.xyz, normalWS, triplanarScale, rock_albedo, rock_normal, rock_arm, rock_height);

    // TODO(gmodarelli): Blend more than 2 layers?
    float b1, b2;
    CalculateBlendingFactors(grass_height, rock_height, slope, 1.0f - slope, b1, b2);
    float3 albedo = HeightBlend(grass_albedo.rgb, rock_albedo.rgb, b1, b2);
    normalWS = normalize(HeightBlend(grass_normal, rock_normal, b1, b2));
    float3 arm = HeightBlend(grass_arm, rock_arm, b1, b2);

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(normalWS, 1.0f);
    Out.GBuffer2 = float4(arm, 1.0f);

    RETURN(Out);
}
