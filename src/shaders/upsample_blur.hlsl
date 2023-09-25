#include "common.hlsli"

#define ROOT_SIGNATURE \
    "CBV(b0), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_LINEAR_MIP_POINT, visibility = SHADER_VISIBILITY_PIXEL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

Texture2D source_texture : register(t0);
SamplerState sam_linear_clamp : register(s0);

struct DrawConst {
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
    float offsetX = cbv_draw_const.filter_radius;
    float offsetY = cbv_draw_const.filter_radius;

    // Take 9 samples around the current texel (cc):
    //
    // tl tt tr
    // ll cc rr
    // bl bb br
    //
    // Convention:
    // - cc: current
    // - tl: top left (etc)
    // - br: bottom right (etc)

    // clang-format off
    float4 tl = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - offsetX, input.uv.y + offsetY));
    float4 tt = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,           input.uv.y + offsetY));
    float4 tr = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + offsetX, input.uv.y + offsetY));

    float4 ll = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - offsetX, input.uv.y          ));
    float4 cc = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,           input.uv.y          ));
    float4 rr = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + offsetX, input.uv.y          ));

    float4 bl = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - offsetX, input.uv.y - offsetY));
    float4 bb = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,           input.uv.y - offsetY));
    float4 br = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + offsetX, input.uv.y - offsetY));
    // clang-format on

    // Apply weighted distribution by using a 3x3 tent filter:
    // | 1 2 1 |
    // | 2 4 2 | * 1/16
    // | 1 2 1 |
    float4 upsample_blur = cc * 4.0;
    upsample_blur += (tt + ll + rr + bb) * 2.0;
    upsample_blur += (tl + tr + bl + br) * 1.0;
    upsample_blur *= 1.0 / 16.0;

    return upsample_blur;
}