#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

SamplerState sam_aniso_clamp : register(s0);

struct DrawConst {
    uint hdr_texture_index;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);

float3 reinhard(float3 hdr, float k = 1.0f) { return hdr / (hdr + k); }

//==========================================================================================
// ACES
//==========================================================================================

//  Baking Lab
//  by MJP and David Neubelt
//  http://mynameismjp.wordpress.com/
//  All code licensed under the MIT license

// sRGB => XYZ => D65_2_D60 => AP1 => RRT_SAT
static const float3x3 aces_mat_input =
{
    {0.59719, 0.35458, 0.04823},
    {0.07600, 0.90834, 0.01566},
    {0.02840, 0.13383, 0.83777}
};

// ODT_SAT => XYZ => D60_2_D65 => sRGB
static const float3x3 aces_mat_output =
{
    { 1.60475, -0.53108, -0.07367},
    {-0.10208,  1.10813, -0.00605},
    {-0.00327, -0.07276,  1.07602}
};

float3 RRTAndODTFit(float3 v)
{
    float3 a = v * (v + 0.0245786f) - 0.000090537f;
    float3 b = v * (0.983729f * v + 0.4329510f) + 0.238081f;
    return a / b;
}

float3 aces(float3 color)
{
    color = mul(aces_mat_input, color);

    // Apply RRT and ODT
    color = RRTAndODTFit(color);

    color = mul(aces_mat_output, color);

    // Clamp to [0, 1]
    color = saturate(color);

    return color;
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

    float3 color = gamma(aces(hdr_texture.Sample(sam_aniso_clamp, input.uv).rgb));
    return float4(color, 1.0);
}