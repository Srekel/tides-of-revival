#define DIRECT3D12
#define STAGE_FRAG

#include "terrain_gbuffer_resources.hlsli"
#include "utils.hlsli"
#include "triplanar_mapping.hlsli"
#include "FastNoiseLite.hlsli"

float3 BlendMode_SoftLight(float3 base, float3 blend);

// Triplanar Sampling
// =================
float3 TriplanarSample(Texture2D texture, SamplerState samplerState, float3 positionWS, float3 normalWS, float projectionScale) {
    positionWS /= projectionScale;
    float3 projectionSigns = sign(normalWS);

    float2 uvx = positionWS.zy * float2(projectionSigns.x, -1.0f);
    float2 uvy = positionWS.xz * float2(1.0f, -1.0f);
    float2 uvz = positionWS.xy * float2(projectionSigns.z * -1.0f, -1.0f);

    float3 dx = texture.Sample(samplerState, uvx).rgb;
    float3 dy = texture.Sample(samplerState, uvy).rgb;
    float3 dz = texture.Sample(samplerState, uvz).rgb;

    float3 weights = Triplanar_GenerateWeights(normalWS);
    return dx * weights.x + dy * weights.y + dz * weights.z;
}

float3 TriplanarSampleNormals(Texture2D texture, SamplerState samplerState, float3 positionWS, float3 normalWS, float projectionScale) {
    positionWS /= projectionScale;
    float3 projectionSigns = sign(normalWS);

    float2 uvx = positionWS.zy * float2(projectionSigns.x, -1.0f);
    float2 uvy = positionWS.xz * float2(1.0f, -1.0f);
    float2 uvz = positionWS.xy * float2(projectionSigns.z * -1.0f, -1.0f);

    float3 tx = ReconstructNormal(texture.Sample(samplerState, uvx), 1.0f);
    float3 ty = ReconstructNormal(texture.Sample(samplerState, uvy), 1.0f);
    float3 tz = ReconstructNormal(texture.Sample(samplerState, uvz), 1.0f);

    // float3 N = normalWS;
    // float3 worldXAxis = float3(1, 0, 0);
    // float3 worldYAxis = float3(0, 1, 0);
    // float3 worldZAxis = float3(0, 0, 1);

    // // Adjust Sampled X Plane
    // {
    //     float3 basisZ = N;

    //     float3 basisY = normalize(cross(N, worldYAxis * projectionSigns.x * -1.0f));
    //     basisY = dot(basisY, basisY) != 0.0f ? basisY : worldYAxis;

    //     float3 basisX = cross(basisY, N);
    //     basisX = dot(basisX, basisX) != 0.0f ? basisX : worldYAxis;

    //     tx = mul(float3x3(basisX, basisY, basisZ), tx);
    // }

    // // Adjust Sampled Y Plane
    // {
    //     float3 basisZ = N;

    //     float3 basisY = normalize(cross(N, worldXAxis * projectionSigns.y));
    //     basisY = dot(basisY, basisY) != 0.0f ? basisY : worldXAxis;

    //     float3 basisX = cross(basisY, N);
    //     basisX = dot(basisX, basisX) != 0.0f ? basisX : worldXAxis;

    //     ty = mul(float3x3(basisX, basisY, basisZ), ty);
    // }

    // // Adjust Sampled Z Plane
    // {
    //     float3 basisZ = N;

    //     float3 basisY = normalize(cross(N, worldXAxis));
    //     basisY = dot(basisY, basisY) != 0.0f ? basisY : worldXAxis;

    //     float3 basisX = cross(basisY, N);
    //     basisX = dot(basisX, basisX) != 0.0f ? basisX : worldXAxis;

    //     tz = mul(float3x3(basisX, basisY, basisZ), tz);
    // }

    return Triplanar_Blend(tx, ty, tz, normalWS);
}

// Terrain Layer sampling
// ======================
void SampleTerrainLayer(uint layer_index, float3 P, float3 N, float triplanarScale, float farTiling, float t, out float3 albedo, out float3 normal, out float3 arm) {
    SamplerState samplerState = g_linear_repeat_sampler;
    TerrainLayerTextureIndices terrain_layer = g_layers[layer_index];

    Texture2D diffuseTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.diffuseIndex)];
    Texture2D armTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.armIndex)];
    Texture2D normalTexture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layer.normalIndex)];

    float3 albedoNear = TriplanarSample(diffuseTexture, samplerState, P, N, triplanarScale);
    float3 armNear = TriplanarSample(armTexture, samplerState, P, N, triplanarScale);
    float3 normalNear = TriplanarSampleNormals(normalTexture, samplerState, P, N, triplanarScale);

    float3 albedoFar = TriplanarSample(diffuseTexture, samplerState, P / farTiling, N, triplanarScale);
    float3 armFar = TriplanarSample(armTexture, samplerState, P / farTiling, N, triplanarScale);
    float3 normalFar = TriplanarSampleNormals(normalTexture, samplerState, P / farTiling, N, triplanarScale);

    t = smoothstep(0.2, 0.8, t);
    albedo = lerp(albedoNear, albedoFar, t);
    arm = lerp(armNear, armFar, t);
    normal = lerp(normalNear, normalFar, t);
}

GBufferOutput PS_MAIN(TerrainVSOutput Input, float3 barycentrics : SV_Barycentrics) {
    INIT_MAIN;
    GBufferOutput Out;

    ByteAddressBuffer instanceTransformBuffer = ResourceDescriptorHeap[g_instanceRootConstants.instanceDataBufferIndex];
    uint instanceIndex = Input.InstanceID + g_instanceRootConstants.startInstanceLocation;
    TerrainInstanceData instance = instanceTransformBuffer.Load<TerrainInstanceData>(instanceIndex * sizeof(TerrainInstanceData));

    const float3 P = Input.PositionWS.xyz;
    const float3 V = normalize(g_cam_pos.xyz - P);
    float3 N = normalize(Input.NormalWS);

    // Reduce reflection at grazing angles
    float fresnel = pow5(saturate(1.0f - dot(N, V)));
    fresnel *= fresnel;

    float slope = abs(N.y);
    slope = smoothstep(g_black_point, g_white_point, slope);

    uint grass_layer_index = 1;
    uint rock_layer_index = 2;
    uint snow_layer_index = 3;

    float triplanarScale = 1;

    float cameraDistance = distance(g_cam_pos.xyz, P);
    cameraDistance = saturate(cameraDistance / (g_tiling_distance_max * 10));

    float3 grass_albedo;
    float3 grass_normal;
    float3 grass_arm;
    SampleTerrainLayer(grass_layer_index, Input.PositionWS.xyz, N, 8, 20, cameraDistance, grass_albedo, grass_normal, grass_arm);

    float3 rock_albedo;
    float3 rock_normal;
    float3 rock_arm;
    SampleTerrainLayer(rock_layer_index, Input.PositionWS.xyz, N, 32, 20, cameraDistance, rock_albedo, rock_normal, rock_arm);

    float3 snow_albedo;
    float3 snow_normal;
    float3 snow_arm;
    SampleTerrainLayer(snow_layer_index, Input.PositionWS.xyz, N, 32, 20, cameraDistance, snow_albedo, snow_normal, snow_arm);

    // Macro-Variation on grass
    {
        Texture2D rustTexture = ResourceDescriptorHeap[g_rust_texture_index];
        float rustSample1 = rustTexture.Sample(g_linear_repeat_sampler, Input.PositionWS.xz / 1439).r;
        float rustSample2 = rustTexture.Sample(g_linear_repeat_sampler, Input.PositionWS.xz / 1873).r;
        float rustSample3 = rustTexture.Sample(g_linear_repeat_sampler, Input.PositionWS.xz / 211).r;
        float rustSample = saturate((rustSample1 + rustSample2 + rustSample3) / 3.0);
        grass_albedo = lerp(grass_albedo, BlendMode_SoftLight(grass_albedo, rustSample.rrr), 0.5);
    }

    // TODO(gmodarelli): Height-blend
    float3 albedo = lerp(rock_albedo, grass_albedo, slope);
    float3 arm = lerp(rock_arm, grass_arm, slope);
    N = normalize(lerp(rock_normal, grass_normal, slope));

    // Blend in snow
    const float snow_height_fudge = 200;
    const float snow_height_transition = 10;
    fnl_state state = fnlCreateState();
    state.fractal_type = FNL_FRACTAL_FBM;
    state.frequency = 0.02;

    float noise = fnlGetNoise2D(state, Input.PositionWS.x, Input.PositionWS.z) * snow_height_fudge;
    float snow_height = 800 + noise;
    float world_height_mask = smoothstep(snow_height, snow_height + snow_height_transition, Input.PositionWS.y); // saturate(inverseLerp(0, 850, Input.PositionWS.y));
    world_height_mask *= smoothstep(0.70, 0.701, saturate(dot(float3(0, 1, 0), N) * 0.5 + 0.5));

    albedo = lerp(albedo, snow_albedo, world_height_mask);
    N = lerp(N, snow_normal, world_height_mask);
    arm = lerp(arm, snow_arm, world_height_mask);

    arm.g = lerp(1.0f, arm.g, fresnel);
    float reflectance = lerp(0.0f, 0.5f, fresnel);

    // const float4 lod_to_color[4] = {
    //     float4(0,1,0,1),
    //     float4(0,0,1,1),
    //     float4(1,1,0,1),
    //     float4(1,0,0,1),
    // };
    // Out.GBuffer0 = float4(albedo, 1.0f) * lod_to_color[instance.lod];

    Out.GBuffer0 = float4(albedo, 1.0f);
    Out.GBuffer1 = float4(N, 1.0f);
    Out.GBuffer2 = float4(arm, reflectance);

    RETURN(Out);
}

// ------------------------------------------------------------------------------
//  Public Domain
// ------------------------------------------------------------------------------
// This is free and unencumbered software released into the public domain.
//
// Anyone is free to copy, modify, publish, use, compile, sell, or
// distribute this software, either in source code form or as a compiled
// binary, for any purpose, commercial or non-commercial, and by any
// means.
//
// In jurisdictions that recognize copyright laws, the author or authors
// of this software dedicate any and all copyright interest in the
// software to the public domain. We make this dedication for the benefit
// of the public at large and to the detriment of our heirs and
// successors. We intend this dedication to be an overt act of
// relinquishment in perpetuity of all present and future rights to this
// software under copyright law.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
// OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//
// For more information, please refer to <http://unlicense.org/>

//******************************************************************************
// Darkens or lightens the colors, depending on the blend color.
//******************************************************************************
float BlendMode_SoftLight(float base, float blend)
{
    if (blend <= 0.5)
    {
        return base - (1 - 2 * blend) * base * (1 - base);
    }
    else
    {
        float d = (base <= 0.25) ? ((16 * base - 12) * base + 4) * base : sqrt(base);
        return base + (2 * blend - 1) * (d - base);
    }
}

float3 BlendMode_SoftLight(float3 base, float3 blend)
{
    return float3(BlendMode_SoftLight(base.r, blend.r),
                  BlendMode_SoftLight(base.g, blend.g),
                  BlendMode_SoftLight(base.b, blend.b));
}
