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

#include "ShaderUtility.hlsli"

Texture2D<float3> MainBuffer : register(t0, UPDATE_FREQ_PER_FRAME);
Texture2D<float4> OverlayBuffer : register(t1, UPDATE_FREQ_PER_FRAME);

float4 main(float4 position : SV_Position) : SV_Target0
{
    // float3 MainColor = ApplyDisplayProfile(MainBuffer[(int2)position.xy], DISPLAY_PLANE_FORMAT);
    float3 MainColor = ApplyDisplayProfile(MainBuffer[(int2)position.xy], LDR_COLOR_FORMAT);
    float4 OverlayColor = OverlayBuffer[(int2)position.xy];
    return float4(OverlayColor.rgb + MainColor.rgb * (1.0 - OverlayColor.a), 0.0);
}
