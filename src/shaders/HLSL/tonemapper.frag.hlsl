// Based on https://github.com/microsoft/DirectX-Graphics-Samples/blob/master/MiniEngine/Core/Shaders/CompositeSDRPS.hlsl

#include "../FSL/d3d.h"

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

#include "shader_utility.hlsli"

Texture2D<float3> HDRBuffer : register(t0, UPDATE_FREQ_PER_FRAME);

float4 main(float4 position : SV_Position) : SV_Target0
{
    float3 SDRColor = ApplyDisplayProfile(HDRBuffer[(int2)position.xy], LDR_COLOR_FORMAT);
    return float4(SDRColor, 1.0);
}
