// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/UpsampleBlurCS.hlsl

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
// The CS for combining a lower resolution bloom buffer with a higher resolution buffer
// (via bilinear upsampling) and then guassian blurring the resultant buffer.
//
// For the intended bloom blurring algorithm, it is expected that this shader will be
// used repeatedly to upsample and blur successively higher resolutions until the final
// bloom buffer is the destination.
//

// #include "PostEffectsRS.hlsli"

Texture2D<float3> higher_res_buffer : register( t0, UPDATE_FREQ_PER_DRAW );
Texture2D<float3> lower_res_buffer : register( t1, UPDATE_FREQ_PER_DRAW );
SamplerState linear_border_sampler : register( s1 );
RWTexture2D<float3> result : register( u0, UPDATE_FREQ_PER_DRAW );

cbuffer cb0 : register(b0, UPDATE_FREQ_PER_DRAW)
{
    float2 g_inverse_dimensions;
    float g_upsample_blend_factor;
}

// The guassian blur weights (derived from Pascal's triangle)
static const float k_weights_5[3] = { 6.0f / 16.0f, 4.0f / 16.0f, 1.0f / 16.0f };
static const float k_weights_7[4] = { 20.0f / 64.0f, 15.0f / 64.0f, 6.0f / 64.0f, 1.0f / 64.0f };
static const float k_weights_9[5] = { 70.0f / 256.0f, 56.0f / 256.0f, 28.0f / 256.0f, 8.0f / 256.0f, 1.0f / 256.0f };

float3 Blur5( float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h, float3 i )
{
    return k_weights_5[0]*e + k_weights_5[1]*(d+f) + k_weights_5[2]*(c+g);
}

float3 Blur7( float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h, float3 i )
{
    return k_weights_7[0]*e + k_weights_7[1]*(d+f) + k_weights_7[2]*(c+g) + k_weights_7[3]*(b+h);
}

float3 Blur9( float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h, float3 i )
{
    return k_weights_9[0]*e + k_weights_9[1]*(d+f) + k_weights_9[2]*(c+g) + k_weights_9[3]*(b+h) + k_weights_9[4]*(a+i);
}

#define BlurPixels Blur9

// 16x16 pixels with an 8x8 center that we will be blurring writing out.  Each uint is two color channels packed together
groupshared uint cache_r[128];
groupshared uint cache_g[128];
groupshared uint cache_b[128];

void Store2Pixels( uint index, float3 pixel1, float3 pixel2 )
{
    cache_r[index] = f32tof16(pixel1.r) | f32tof16(pixel2.r) << 16;
    cache_g[index] = f32tof16(pixel1.g) | f32tof16(pixel2.g) << 16;
    cache_b[index] = f32tof16(pixel1.b) | f32tof16(pixel2.b) << 16;
}

void Load2Pixels( uint index, out float3 pixel1, out float3 pixel2 )
{
    uint3 rgb = uint3(cache_r[index], cache_g[index], cache_b[index]);
    pixel1 = f16tof32(rgb);
    pixel2 = f16tof32(rgb >> 16);
}

void Store1Pixel( uint index, float3 pixel )
{
    cache_r[index] = asuint(pixel.r);
    cache_g[index] = asuint(pixel.g);
    cache_b[index] = asuint(pixel.b);
}

void Load1Pixel( uint index, out float3 pixel )
{
    pixel = asfloat( uint3(cache_r[index], cache_g[index], cache_b[index]) );
}

// Blur two pixels horizontally.  This reduces LDS reads and pixel unpacking.
void BlurHorizontally( uint out_index, uint leftmost_index )
{
    float3 s0, s1, s2, s3, s4, s5, s6, s7, s8, s9;
    Load2Pixels( leftmost_index + 0, s0, s1 );
    Load2Pixels( leftmost_index + 1, s2, s3 );
    Load2Pixels( leftmost_index + 2, s4, s5 );
    Load2Pixels( leftmost_index + 3, s6, s7 );
    Load2Pixels( leftmost_index + 4, s8, s9 );
    
    Store1Pixel(out_index  , BlurPixels(s0, s1, s2, s3, s4, s5, s6, s7, s8));
    Store1Pixel(out_index+1, BlurPixels(s1, s2, s3, s4, s5, s6, s7, s8, s9));
}

void BlurVertically( uint2 pixel_coord, uint topmost_index )
{
    float3 s0, s1, s2, s3, s4, s5, s6, s7, s8;
    Load1Pixel( topmost_index   , s0 );
    Load1Pixel( topmost_index+ 8, s1 );
    Load1Pixel( topmost_index+16, s2 );
    Load1Pixel( topmost_index+24, s3 );
    Load1Pixel( topmost_index+32, s4 );
    Load1Pixel( topmost_index+40, s5 );
    Load1Pixel( topmost_index+48, s6 );
    Load1Pixel( topmost_index+56, s7 );
    Load1Pixel( topmost_index+64, s8 );

    result[pixel_coord] = BlurPixels(s0, s1, s2, s3, s4, s5, s6, s7, s8);
}

[numthreads( 8, 8, 1 )]
void main( uint3 group_id : SV_GroupID, uint3 group_thread_id : SV_GroupThreadID, uint3 dispatch_thread_id : SV_DispatchThreadID )
{
    //
    // Load 4 pixels per thread into LDS
    //
    int2 group_ul = (group_id.xy << 3) - 4;                // Upper-left pixel coordinate of group read location
    int2 thread_ul = (group_thread_id.xy << 1) + group_ul;        // Upper-left pixel coordinate of quad that this thread will read

    //
    // Store 4 blended-but-unblurred pixels in LDS
    //
    float2 uvUL = (float2(thread_ul) + 0.5) * g_inverse_dimensions;
    float2 uvLR = uvUL + g_inverse_dimensions;
    float2 uvUR = float2(uvLR.x, uvUL.y);
    float2 uvLL = float2(uvUL.x, uvLR.y);
    int destIdx = group_thread_id.x + (group_thread_id.y << 4);

    float3 pixel1a = lerp(higher_res_buffer[thread_ul + uint2(0, 0)], lower_res_buffer.SampleLevel(linear_border_sampler, uvUL, 0.0f), g_upsample_blend_factor);
    float3 pixel1b = lerp(higher_res_buffer[thread_ul + uint2(1, 0)], lower_res_buffer.SampleLevel(linear_border_sampler, uvUR, 0.0f), g_upsample_blend_factor);
    Store2Pixels(destIdx+0, pixel1a, pixel1b);

    float3 pixel2a = lerp(higher_res_buffer[thread_ul + uint2(0, 1)], lower_res_buffer.SampleLevel(linear_border_sampler, uvLL, 0.0f), g_upsample_blend_factor);
    float3 pixel2b = lerp(higher_res_buffer[thread_ul + uint2(1, 1)], lower_res_buffer.SampleLevel(linear_border_sampler, uvLR, 0.0f), g_upsample_blend_factor);
    Store2Pixels(destIdx+8, pixel2a, pixel2b);

    GroupMemoryBarrierWithGroupSync();

    //
    // Horizontally blur the pixels in Cache
    //
    uint row = group_thread_id.y << 4;
    BlurHorizontally(row + (group_thread_id.x << 1), row + group_thread_id.x + (group_thread_id.x & 4));

    GroupMemoryBarrierWithGroupSync();

    //
    // Vertically blur the pixels and write the result to memory
    //
    BlurVertically(dispatch_thread_id.xy, (group_thread_id.y << 3) + group_thread_id.x);
}
