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

// Based on Call of Duty 2014 ACM Siggraph Paper
[RootSignature(ROOT_SIGNATURE)]
float4 psDownsample(FullscreenTriangleOutput input) : SV_Target
{
    float2 source_texel_size = 1.0 / cbv_draw_const.source_resolution;

    // Determine texel size.
    // When rendering from one mip level to another mip of the same texture,
    // calling code should use GL_TEXTURE_BASE_LEVEL and GL_TEXTURE_MAX_LEVEL to
    // limit the textures that can be sampled from. When doing this,
    // textureSize(..., 0) will correctly use the BASE mip level.
    float offsetX = source_texel_size.x;
    float offsetY = source_texel_size.y;

    // Take 13 samples around the current texel (ccc):
    //
    // etl --- ett --- etr
    // --- itl --- itr ---
    // ell --- ccc --- err
    // --- ibl --- ibr ---
    // ebl --- ebb --- ebr
    //
    // Convention:
    // - ccc: current
    // - itl: interior top left (etc)
    // - ebr: exterior bottom right (etc)

    // clang-format off
    float4 etl = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - 2 * offsetX, input.uv.y + 2 * offsetY));
    float4 ett = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,               input.uv.y + 2 * offsetY));
    float4 etr = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + 2 * offsetX, input.uv.y + 2 * offsetY));

    float4 ell = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - 2 * offsetX, input.uv.y              ));
    float4 ccc = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,               input.uv.y              ));
    float4 err = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + 2 * offsetX, input.uv.y              ));

    float4 ebl = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - 2 * offsetX, input.uv.y - 2 * offsetY));
    float4 ebb = source_texture.Sample(sam_linear_clamp, float2(input.uv.x,               input.uv.y - 2 * offsetY));
    float4 ebr = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + 2 * offsetX, input.uv.y - 2 * offsetY));

    float4 itl = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - offsetX, input.uv.y + offsetY));
    float4 itr = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + offsetX, input.uv.y + offsetY));
    float4 ibl = source_texture.Sample(sam_linear_clamp, float2(input.uv.x - offsetX, input.uv.y - offsetY));
    float4 ibr = source_texture.Sample(sam_linear_clamp, float2(input.uv.x + offsetX, input.uv.y - offsetY));
    // clang-format on

    // We want to weigh the sample amongst 5 square regions:
    // - 50% weight for 1 center region comprised of itl,itr,ibl,ibr (including
    //   the current texel).
    // - 12.5% weight each for 4 regions around the corners (for example, the
    //   top-left region of etl,ett,ell,ccc)
    //
    // However, if we just add up the samples naively, we'll double-count since
    // the regions overlap. To preserve energy, since each region is comprised of
    // exactly 5 samples, we redistribute the weights between all samples such
    // that:
    //   sample_weight =
    //       sum((region_weight / 5) for each region that sample is in)
    //
    // This yields the following distribution. The weights all add up to 1.
    float4 downsample = ccc * 0.2;
    downsample += (itl + itr + ibl + ibr) * 0.125;
    downsample += (ett + ell + err + ebb) * 0.05;
    downsample += (etl + etr + ebl + ebr) * 0.025;

    if (cbv_draw_const.mip_level == 0) {
        downsample = max(downsample, 0.00001);
    }

    return downsample;
}