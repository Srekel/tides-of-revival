#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_PIXEL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

SamplerState sam_linear_clamp : register(s0);

struct DrawConst {
    uint source_texture_index;
    float filter_radius;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);

[RootSignature(ROOT_SIGNATURE)]
FullscreenTriangleOutput vsFullscreenTriangle(uint vertexID : SV_VertexID)
{
    FullscreenTriangleOutput output;

    output.uv = float2((vertexID << 1) & 2, vertexID & 2);
    output.position = float4(output.uv * float2(2, -2) + float2(-1, 1), 0, 1);

    return output;
}

// Based on Call of Duty 2014 ACM Siggraph Paper
[RootSignature(ROOT_SIGNATURE)]
float4 psUpsampleBlur(FullscreenTriangleOutput input) : SV_Target
{
    // The filter kernel is applied with a radius, specified in texture
    // coordinates, so that the radius will vary across mip resolutions.
    float x = cbv_draw_const.filter_radius;
    float y = cbv_draw_const.filter_radius;
    Texture2D source_texture = ResourceDescriptorHeap[cbv_draw_const.source_texture_index];

    // Take 9 samples around current texel:
    // a - b - c
    // d - e - f
    // g - h - i
    // === ('e' is the current texel) ===
    float4 a = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - x, input.uv.y + y));
    float4 b = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,     input.uv.y + y));
    float4 c = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + x, input.uv.y + y));

    float4 d = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - x, input.uv.y));
    float4 e = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,     input.uv.y));
    float4 f = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + x, input.uv.y));

    float4 g = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - x, input.uv.y - y));
    float4 h = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,     input.uv.y - y));
    float4 i = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + x, input.uv.y - y));

    // Apply weighted distribution by using a 3x3 tent filter:
    //  1   | 1 2 1 |
    // -- * | 2 4 2 |
    // 16   | 1 2 1 |
    float4 upsample_blur = e * 4.0;
    upsample_blur += (b + d + f + h) * 2.0;
    upsample_blur += (a + c + g + i);
    upsample_blur *= 1.0 / 16.0;

    return upsample_blur;
}