// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/BlurCS.hlsl

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
// The CS for guassian blurring a single RGB buffer.
//
// For the intended bloom blurring algorithm, this shader is expected to be used only on
// the lowest resolution bloom buffer before starting the series of upsample-and-blur
// passes.

// #include "PostEffectsRS.hlsli"

Texture2D<float3> input_buffer : register( t0, UPDATE_FREQ_PER_FRAME );
RWTexture2D<float3> result : register( u0, UPDATE_FREQ_PER_FRAME );

// The guassian blur weights (derived from Pascal's triangle)
static const float k_weights[5] = { 70.0f / 256.0f, 56.0f / 256.0f, 28.0f / 256.0f, 8.0f / 256.0f, 1.0f / 256.0f };

float3 BlurPixels( float3 a, float3 b, float3 c, float3 d, float3 e, float3 f, float3 g, float3 h, float3 i )
{
    return k_weights[0]*e + k_weights[1]*(d+f) + k_weights[2]*(c+g) + k_weights[3]*(b+h) + k_weights[4]*(a+i);
}

// 16x16 pixels with an 8x8 center that we will be blurring writing out. Each uint is two color channels packed together
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
    uint rr = cache_r[index];
    uint gg = cache_g[index];
    uint bb = cache_b[index];
    pixel1 = float3( f16tof32(rr      ), f16tof32(gg      ), f16tof32(bb      ) );
    pixel2 = float3( f16tof32(rr >> 16), f16tof32(gg >> 16), f16tof32(bb >> 16) );
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

// Blur two pixels horizontally. This reduces LDS reads and pixel unpacking.
void BlurHorizontally( uint out_index, uint leftmost_index )
{
    float3 s0, s1, s2, s3, s4, s5, s6, s7, s8, s9;
    Load2Pixels( leftmost_index + 0, s0, s1 );
    Load2Pixels( leftmost_index + 1, s2, s3 );
    Load2Pixels( leftmost_index + 2, s4, s5 );
    Load2Pixels( leftmost_index + 3, s6, s7 );
    Load2Pixels( leftmost_index + 4, s8, s9 );
    
    // Be sure to finish loading values before we rewrite them.
    GroupMemoryBarrierWithGroupSync();
 
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
    int2 GroupUL = (group_id.xy << 3) - 4;           // Upper-left pixel coordinate of group read location
    int2 ThreadUL = (group_thread_id.xy << 1) + GroupUL;   // Upper-left pixel coordinate of quad that this thread will read

    //
    // Store 4 unblurred pixels in LDS
    //
    int destIdx = group_thread_id.x + (group_thread_id.y << 4);
    Store2Pixels(destIdx+0, input_buffer[ThreadUL + uint2(0, 0)], input_buffer[ThreadUL + uint2(1, 0)]);
    Store2Pixels(destIdx+8, input_buffer[ThreadUL + uint2(0, 1)], input_buffer[ThreadUL + uint2(1, 1)]);

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
