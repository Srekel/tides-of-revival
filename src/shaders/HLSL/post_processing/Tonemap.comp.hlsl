// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/TonemapCS.hlsl

#include "../../FSL/d3d.h"

//
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

#include "../ToneMappingUtility.hlsli"
#include "../PixelPacking.hlsli"

StructuredBuffer<float> Exposure : register(t0, UPDATE_FREQ_PER_FRAME);
Texture2D<float3> Bloom : register(t1, UPDATE_FREQ_PER_FRAME);
RWTexture2D<float3> ColorRW : register(u0, UPDATE_FREQ_PER_FRAME);
RWTexture2D<float> OutLuma : register(u1, UPDATE_FREQ_PER_FRAME);
SamplerState g_linear_clamp_edge_sampler : register(s0);

cbuffer CB0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float2 g_RcpBufferDim;
    float g_BloomStrength;
    float PaperWhiteRatio; // PaperWhite / MaxBrightness
    float MaxBrightness;
};

[numthreads(8, 8, 1)] void
main(uint3 DTid : SV_DispatchThreadID)
{
    float2 TexCoord = (DTid.xy + 0.5) * g_RcpBufferDim;

    // Load HDR and bloom
    float3 hdrColor = ColorRW[DTid.xy];

    hdrColor += g_BloomStrength * Bloom.SampleLevel(g_linear_clamp_edge_sampler, TexCoord, 0);
    hdrColor *= Exposure[0];

    // Tone map to SDR
    float3 sdrColor = TM_Stanard(hdrColor);

    ColorRW[DTid.xy] = sdrColor;
    OutLuma[DTid.xy] = RGBToLogLuminance(sdrColor);
}
