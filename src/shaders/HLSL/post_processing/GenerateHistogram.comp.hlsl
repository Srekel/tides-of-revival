// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/GenerateHistogramCS.hlsl

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
// The group size is 16x16, but one group iterates over an entire 16-wide column of pixels (384 pixels tall)
// Assuming the total workspace is 640x384, there will be 40 thread groups computing the histogram in parallel.
// The histogram measures logarithmic luminance ranging from 2^-12 up to 2^4.  This should provide a nice window
// where the exposure would range from 2^-4 up to 2^4.

Texture2D<uint> LumaBuf : register(t0, UPDATE_FREQ_PER_FRAME);
RWByteAddressBuffer Histogram : register(u0, UPDATE_FREQ_PER_FRAME);

groupshared uint g_TileHistogram[256];

cbuffer CB0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    uint kBufferHeight;
}

[numthreads(16, 16, 1)] void main(uint GI : SV_GroupIndex, uint3 DTid : SV_DispatchThreadID)
{
    g_TileHistogram[GI] = 0;

    GroupMemoryBarrierWithGroupSync();

    // Loop until the entire column has been processed
    for (uint2 ST = DTid.xy; ST.y < kBufferHeight; ST.y += 16)
    {
        uint QuantizedLogLuma = LumaBuf[ST];
        InterlockedAdd(g_TileHistogram[QuantizedLogLuma], 1);
    }

    GroupMemoryBarrierWithGroupSync();

    Histogram.InterlockedAdd(GI * 4, g_TileHistogram[GI]);
}
