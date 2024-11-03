// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/ApplyBlumCS.hlsl

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

// #include "ShaderUtility.hlsli"
// #include "PostEffectsRS.hlsli"
// #include "PixelPacking.hlsli"

Texture2D<float3> bloom_buffer : register( t0, UPDATE_FREQ_PER_FRAME );
RWTexture2D<float3> scene_color : register( u0, UPDATE_FREQ_PER_FRAME );
// TODO(gmodarelli): Implement Luma
// RWTexture2D<float> OutLuma : register( u1 );
SamplerState g_linear_clamp_edge_sampler : register( s0 );

cbuffer cb0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float2 g_rpc_buffer_dimensions;
    float g_bloom_strength;
};

[numthreads( 8, 8, 1 )]
void main( uint3 dispatch_thread_id : SV_DispatchThreadID )
{
    float2 tex_coord = (dispatch_thread_id.xy + 0.5) * g_rpc_buffer_dimensions;

    // Load LDR and bloom
    float3 ldr_color = scene_color[dispatch_thread_id.xy] + g_bloom_strength * bloom_buffer.SampleLevel(g_linear_clamp_edge_sampler, tex_coord, 0);

    scene_color[dispatch_thread_id.xy] = ldr_color;
    // TODO(gmodarelli): Implement Luma
    // OutLuma[dispatch_thread_id.xy] = RGBToLogLuminance(ldr_color);
}
