// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/DownsampleBloomAllCS.hlsl

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
// The CS for downsampling 16x16 blocks of pixels down to 8x8, 4x4, 2x2, and 1x1 blocks.

// #include "PostEffectsRS.hlsli"

Texture2D<float3> bloom_buffer : register( t0, UPDATE_FREQ_PER_FRAME );
RWTexture2D<float3> result_1 : register( u0, UPDATE_FREQ_PER_FRAME );
RWTexture2D<float3> result_2 : register( u1, UPDATE_FREQ_PER_FRAME );
RWTexture2D<float3> result_3 : register( u2, UPDATE_FREQ_PER_FRAME );
RWTexture2D<float3> result_4 : register( u3, UPDATE_FREQ_PER_FRAME );
SamplerState bilinear_clamp_sampler : register( s0 );

cbuffer cb0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float2 g_inverse_dimensions;
}

groupshared float3 g_tile[64];    // 8x8 input pixels

[numthreads( 8, 8, 1 )]
void main( uint group_index : SV_GroupIndex, uint3 dispatch_thread_id : SV_DispatchThreadID )
{
    // You can tell if both x and y are divisible by a power of two with this value
    uint parity = dispatch_thread_id.x | dispatch_thread_id.y;

    // Downsample and store the 8x8 block
    float2 centerUV = (float2(dispatch_thread_id.xy) * 2.0f + 1.0f) * g_inverse_dimensions;
    float3 avgPixel = bloom_buffer.SampleLevel(bilinear_clamp_sampler, centerUV, 0.0f);
    g_tile[group_index] = avgPixel;
    result_1[dispatch_thread_id.xy] = avgPixel;

    GroupMemoryBarrierWithGroupSync();

    // Downsample and store the 4x4 block
    if ((parity & 1) == 0)
    {
        avgPixel = 0.25f * (avgPixel + g_tile[group_index+1] + g_tile[group_index+8] + g_tile[group_index+9]);
        g_tile[group_index] = avgPixel;
        result_2[dispatch_thread_id.xy >> 1] = avgPixel;
    }

    GroupMemoryBarrierWithGroupSync();

    // Downsample and store the 2x2 block
    if ((parity & 3) == 0)
    {
        avgPixel = 0.25f * (avgPixel + g_tile[group_index+2] + g_tile[group_index+16] + g_tile[group_index+18]);
        g_tile[group_index] = avgPixel;
        result_3[dispatch_thread_id.xy >> 2] = avgPixel;
    }

    GroupMemoryBarrierWithGroupSync();

    // Downsample and store the 1x1 block
    if ((parity & 7) == 0)
    {
        avgPixel = 0.25f * (avgPixel + g_tile[group_index+4] + g_tile[group_index+32] + g_tile[group_index+36]);
        result_4[dispatch_thread_id.xy >> 3] = avgPixel;
    }
}
