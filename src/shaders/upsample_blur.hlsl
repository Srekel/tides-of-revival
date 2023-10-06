#include "common.hlsli"

#define ROOT_SIGNATURE \
    "CBV(b0), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_LINEAR_MIP_POINT, visibility = SHADER_VISIBILITY_PIXEL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

Texture2D source_texture : register(t0);
SamplerState sam_linear_clamp : register(s0);

struct DrawConst {
    float2 source_resolution;
    float sample_scale;
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
// 9-tap bilinear upsampler (tent filter)
float4 upsampleTent(Texture2D texture, SamplerState samplerState, float2 uv, float2 texelSize, float sampleScale)
{
    float4 d = texelSize.xyxy * float4(1.0, 1.0, -1.0, 0.0) * sampleScale;

    float4 s;
    s =  texture.Sample(samplerState, uv - d.xy);
    s += texture.Sample(samplerState, uv - d.wy) * 2.0;
    s += texture.Sample(samplerState, uv - d.zy);

    s += texture.Sample(samplerState, uv + d.zw) * 2.0;
    s += texture.Sample(samplerState, uv       ) * 4.0;
    s += texture.Sample(samplerState, uv + d.xw) * 2.0;

    s += texture.Sample(samplerState, uv + d.zy);
    s += texture.Sample(samplerState, uv + d.wy) * 2.0;
    s += texture.Sample(samplerState, uv + d.xy);

    return s * (1.0 / 16.0);
}

[RootSignature(ROOT_SIGNATURE)]
float4 psUpsampleBlur(FullscreenTriangleOutput input) : SV_Target
{
    float2 texelSize = 1.0 / cbv_draw_const.source_resolution;
    return upsampleTent(source_texture, sam_linear_clamp, input.uv, texelSize, cbv_draw_const.sample_scale);
}