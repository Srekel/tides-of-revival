#include "common.hlsli"

#define ROOT_SIGNATURE \
    "CBV(b0), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_LINEAR_MIP_POINT, visibility = SHADER_VISIBILITY_PIXEL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

Texture2D source_texture : register(t0);
SamplerState sam_linear_clamp : register(s0);

struct DrawConst {
    float2 source_resolution;
    uint mip_level;
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

// Better, temporally stable box filtering
// [Jimenez14] http://goo.gl/eomGso
// . . . . . . .
// . A . B . C .
// . . D . E . .
// . F . G . H .
// . . I . J . .
// . K . L . M .
// . . . . . . .
float4 downsampleBox13Tap(Texture2D texture, SamplerState samplerState, float2 uv, float2 texelSize)
{
    float4 A = texture.Sample(samplerState, uv + texelSize * float2(-1.0, -1.0));
    float4 B = texture.Sample(samplerState, uv + texelSize * float2( 0.0, -1.0));
    float4 C = texture.Sample(samplerState, uv + texelSize * float2( 1.0, -1.0));
    float4 D = texture.Sample(samplerState, uv + texelSize * float2(-0.5, -0.5));
    float4 E = texture.Sample(samplerState, uv + texelSize * float2( 0.5, -0.5));
    float4 F = texture.Sample(samplerState, uv + texelSize * float2(-1.0,  0.0));
    float4 G = texture.Sample(samplerState, uv                                 );
    float4 H = texture.Sample(samplerState, uv + texelSize * float2( 1.0,  0.0));
    float4 I = texture.Sample(samplerState, uv + texelSize * float2(-0.5,  0.5));
    float4 J = texture.Sample(samplerState, uv + texelSize * float2( 0.5,  0.5));
    float4 K = texture.Sample(samplerState, uv + texelSize * float2(-1.0,  1.0));
    float4 L = texture.Sample(samplerState, uv + texelSize * float2( 0.0,  1.0));
    float4 M = texture.Sample(samplerState, uv + texelSize * float2( 1.0,  1.0));

    float2 div = (1.0 / 4.0) * float2(0.5, 0.125);

    float4 o = (D + E + I + J) * div.x;
    o += (A + B + G + F) * div.y;
    o += (B + C + H + G) * div.y;
    o += (F + G + L + K) * div.y;
    o += (G + H + M + L) * div.y;

    return o;
}

// Based on Call of Duty 2014 ACM Siggraph Paper
[RootSignature(ROOT_SIGNATURE)]
float4 psDownsample(FullscreenTriangleOutput input) : SV_Target
{
    float2 texelSize = 1.0 / cbv_draw_const.source_resolution;
    float4 downsample = downsampleBox13Tap(source_texture, sam_linear_clamp, input.uv, texelSize);

    if (cbv_draw_const.mip_level == 0) {
        downsample = max(downsample, 0.00001);
    }

    return downsample;
}