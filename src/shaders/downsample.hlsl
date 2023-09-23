#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_PIXEL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

SamplerState sam_linear_clamp : register(s0);

struct DrawConst {
    uint source_texture_index;
    float2 source_resolution;
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

float3 Powfloat3(float3 v, float p)
{
    return float3(pow(v.x, p), pow(v.y, p), pow(v.z, p));
}

float3 ToSRGB(float3 v)   { return Powfloat3(v, 1.0 / 2.2); }

float sRGBToLuma(float3 col)
{
	return dot(col, float3(0.299f, 0.587f, 0.114f));
}

float KarisAverage(float3 col)
{
	// Formula is 1 / (1 + luma)
	float luma = sRGBToLuma(ToSRGB(col)) * 0.25f;
	return 1.0f / (1.0f + luma);
}

// Based on Call of Duty 2014 ACM Siggraph Paper
[RootSignature(ROOT_SIGNATURE)]
float4 psDownsample(FullscreenTriangleOutput input) : SV_Target
{
    float2 source_texel_size = 1.0 / cbv_draw_const.source_resolution;
    float x = source_texel_size.x;
    float y = source_texel_size.y;

    Texture2D source_texture = ResourceDescriptorHeap[cbv_draw_const.source_texture_index];

    // Take 13 samples around current texel:
    // a - b - c
    // - j - k -
    // d - e - f
    // - l - m -
    // g - h - i
    // === ('e' is the current texel) ===
    float3 a = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - 2 * x, input.uv.y + 2 * y)).rgb;
    float3 b = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,         input.uv.y + 2 * y)).rgb;
    float3 c = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + 2 * x, input.uv.y + 2 * y)).rgb;

    float3 d = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - 2 * x, input.uv.y)).rgb;
    float3 e = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,         input.uv.y)).rgb;
    float3 f = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + 2 * x, input.uv.y)).rgb;

    float3 g = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - 2 * x, input.uv.y - 2 * y)).rgb;
    float3 h = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,         input.uv.y - 2 * y)).rgb;
    float3 i = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + 2 * x, input.uv.y - 2 * y)).rgb;

    float3 j = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - x, input.uv.y + y)).rgb;
    float3 k = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + x, input.uv.y + y)).rgb;
    float3 l = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - x, input.uv.y - y)).rgb;
    float3 m = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + x, input.uv.y - y)).rgb;

    // Apply weighted distribution:
    // 0.5 + 0.125 + 0.125 + 0.125 + 0.125 = 1
    // a,b,d,e * 0.125
    // b,c,e,f * 0.125
    // d,e,g,h * 0.125
    // e,f,h,i * 0.125
    // j,k,l,m * 0.5
    // This shows 5 square areas that are being sampled. But some of them overlap,
    // so to have an energy preserving downsample we need to make some adjustments.
    // The weights are the distributed, so that the sum of j,k,l,m (e.g.)
    // contribute 0.5 to the final color output. The code below is written
    // to effectively yield this sum. We get:
    // 0.125*5 + 0.03125*4 + 0.0625*4 = 1
    float3 downsample = e * 0.2;
    downsample += (j + k + l + m) * 0.125;
    downsample += (b + d + f + h) * 0.05;
    downsample += (a + c + g + i) * 0.025;

    return float4(downsample, 1.0);
}