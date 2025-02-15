// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/ApplyBlumCS.hlsl

#include "../../FSL/d3d.h"

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

#include "../ShaderUtility.hlsli"
#include "../PixelPacking.hlsli"

Texture2D<float3> Bloom : register(t0, UPDATE_FREQ_PER_FRAME);
RWTexture2D<float3> SrcColor : register(u0, UPDATE_FREQ_PER_FRAME);
// TODO(gmodarelli): Implement Luma
// RWTexture2D<float> OutLuma : register( u1 );
SamplerState g_linear_clamp_edge_sampler : register(s0);

cbuffer CB0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float2 g_RcpBufferDim;
    float g_BloomStrength;
};

[numthreads(8, 8, 1)] void main(uint3 DTid : SV_DispatchThreadID)
{
    float2 texCoord = (DTid.xy + 0.5) * g_RcpBufferDim;

    // Load LDR and bloom
    float3 ldrColor = SrcColor[DTid.xy] + g_BloomStrength * Bloom.SampleLevel(g_linear_clamp_edge_sampler, texCoord, 0);

    SrcColor[DTid.xy] = ldrColor;
    // TODO(gmodarelli): Implement Luma
    // OutLuma[DTid.xy] = RGBToLogLuminance(ldrColor);
}
