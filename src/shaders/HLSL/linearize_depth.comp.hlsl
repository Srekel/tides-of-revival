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

// NOTE: We define Root Signatures in zig
// #include "SSAORS.hlsli"
#include "../FSL/d3d.h"

RWTexture2D<float> LinearZ : register(u0, UPDATE_FREQ_PER_FRAME);
Texture2D<float> Depth : register(t0, UPDATE_FREQ_PER_FRAME);

cbuffer CB0 : register(b0, UPDATE_FREQ_PER_FRAME)
{
    float ZMagic;                // (zFar - zNear) / zNear
}

// NOTE: We define Root Signatures in zig
// [RootSignature(SSAO_RootSig)]
[numthreads( 16, 16, 1 )]
void main( uint3 Gid : SV_GroupID, uint GI : SV_GroupIndex, uint3 GTid : SV_GroupThreadID, uint3 DTid : SV_DispatchThreadID )
{
    LinearZ[DTid.xy] = 1.0 / (ZMagic * Depth[DTid.xy] + 1.0);
}
