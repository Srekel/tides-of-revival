#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

SamplerState sam_aniso_clamp : register(s0);

struct DrawConst {
    uint hdr_texture_index;
    uint bloom_texture_index;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);

//
// Simpler approximation to ACES, by Krzysztof Narkowicz.
// https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
//
float3 acesApprox(float3 color) {
  // Obtain original ACES curve by multiplying the input HRD by 0.6
  color *= 0.6;

  float a = 2.51;
  float b = 0.03;
  float c = 2.43;
  float d = 0.59;
  float e = 0.14;

  return saturate((color * (a * color + b)) / (color * (c * color + d) + e));
}

[RootSignature(ROOT_SIGNATURE)]
FullscreenTriangleOutput vsFullscreenTriangle(uint vertexID : SV_VertexID)
{
    FullscreenTriangleOutput output;

    output.uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.position = float4(output.uv * float2(2, -2) + float2(-1, 1), 0, 1);

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
float4 psTonemapping(FullscreenTriangleOutput input) : SV_Target
{
    Texture2D hdr_texture = ResourceDescriptorHeap[cbv_draw_const.hdr_texture_index];
    Texture2D bloom_texture = ResourceDescriptorHeap[cbv_draw_const.bloom_texture_index];

    float3 scene_color = hdr_texture.Sample(sam_aniso_clamp, input.uv).rgb;
    float3 bloom_color = bloom_texture.Sample(sam_aniso_clamp, input.uv).rgb;
    scene_color = lerp(scene_color, bloom_color, 0.004);
    float3 color = acesApprox(scene_color);
    return float4(gamma(color), 1.0);
}