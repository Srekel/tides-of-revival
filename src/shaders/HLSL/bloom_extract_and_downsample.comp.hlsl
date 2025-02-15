// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/BloomExtractAndDownsampleLdrCS.hlsl

#include "../FSL/d3d.h"

// Copyright (c) Microsoft. All rights reserved.
// This code is licensed under the MIT License (MIT).
// THIS CODE IS PROVIDED *AS IS* WITHOUT WARRANTY OF
// ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING ANY
// IMPLIED WARRANTIES OF FITNESS FOR A PARTICULAR
// PURPOSE, MERCHANTABILITY, OR NON-INFRINGEMENT.
//
// Developed by Minigraph
//
// Author:  James Stanard
//
// The CS for extracting bright pixels and downsampling them to an unblurred bloom buffer.

#include "ShaderUtility.hlsli"

SamplerState g_linear_clamp_edge_sampler : register(s0);
Texture2D<float3> source_tex : register(t0, UPDATE_FREQ_PER_FRAME);
StructuredBuffer<float> exposure : register(t1, UPDATE_FREQ_PER_FRAME);
RWTexture2D<float3> bloom_result : register(u0, UPDATE_FREQ_PER_FRAME);
RWTexture2D<uint> luma_result : register(u1, UPDATE_FREQ_PER_FRAME);

cbuffer cb0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float2 g_inverse_output_size;
    float g_bloom_threshold;
}

[numthreads(8, 8, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    // We need the scale factor and the size of one pixel so that our four samples are right in the middle
    // of the quadrant they are covering.
    float2 uv = (DTid.xy + 0.5) * g_inverse_output_size;
    float2 offset = g_inverse_output_size * 0.25;

    // Use 4 bilinear samples to guarantee we don't undersample when downsizing by more than 2x
    float3 color1 = source_tex.SampleLevel(g_linear_clamp_edge_sampler, uv + float2(-offset.x, -offset.y), 0);
    float3 color2 = source_tex.SampleLevel(g_linear_clamp_edge_sampler, uv + float2(offset.x, -offset.y), 0);
    float3 color3 = source_tex.SampleLevel(g_linear_clamp_edge_sampler, uv + float2(-offset.x, offset.y), 0);
    float3 color4 = source_tex.SampleLevel(g_linear_clamp_edge_sampler, uv + float2(offset.x, offset.y), 0);

    float luma1 = RGBToLuminance(color1);
    float luma2 = RGBToLuminance(color2);
    float luma3 = RGBToLuminance(color3);
    float luma4 = RGBToLuminance(color4);

    const float k_small_epsilon = 0.0001;

    float scaled_threshold = g_bloom_threshold * exposure[1]; // Bloom Threshold / Exposure

    // We perform a brightness filter pass, where lone bright pixels will contribute less.
    color1 *= max(k_small_epsilon, luma1 - scaled_threshold) / (luma1 + k_small_epsilon);
    color2 *= max(k_small_epsilon, luma2 - scaled_threshold) / (luma2 + k_small_epsilon);
    color3 *= max(k_small_epsilon, luma3 - scaled_threshold) / (luma3 + k_small_epsilon);
    color4 *= max(k_small_epsilon, luma4 - scaled_threshold) / (luma4 + k_small_epsilon);

    // The shimmer filter helps remove stray bright pixels from the bloom buffer by inversely weighting
    // them by their luminance.  The overall effect is to shrink bright pixel regions around the border.
    // Lone pixels are likely to dissolve completely.  This effect can be tuned by adjusting the shimmer
    // filter inverse strength.  The bigger it is, the less a pixel's luminance will matter.
    const float k_shimmer_filter_inverse_strength = 1.0f;
    float weight1 = 1.0f / (luma1 + k_shimmer_filter_inverse_strength);
    float weight2 = 1.0f / (luma2 + k_shimmer_filter_inverse_strength);
    float weight3 = 1.0f / (luma3 + k_shimmer_filter_inverse_strength);
    float weight4 = 1.0f / (luma4 + k_shimmer_filter_inverse_strength);
    float weight_sum = weight1 + weight2 + weight3 + weight4;

    bloom_result[DTid.xy] = (color1 * weight1 + color2 * weight2 + color3 * weight3 + color4 * weight4) / weight_sum;

    float luma = (luma1 + luma2 + luma3 + luma4) * 0.25;

    // Prevent log(0) and put only pure black pixels in Histogram[0]
    if (luma == 0.0)
    {
        luma_result[DTid.xy] = 0;
    }
    else
    {
        const float min_log = exposure[4];
        const float rcp_log_range = exposure[7];
        float log_luma = saturate((log2(luma) - min_log) * rcp_log_range); // Rescale to [0.0, 1.0]
        luma_result[DTid.xy] = log_luma * 254.0 + 1.0;                     // Rescale to [1, 255]
    }
}
