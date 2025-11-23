#include "../FSL/d3d.h"
#include "color_space_utility.hlsli"

// Buffer visualization modes
#define BUFFER_VISUALIZATION_ALBEDO 0
#define BUFFER_VISUALIZATION_WORLD_NORMAL 1
#define BUFFER_VISUALIZATION_OCCLUSION 2
#define BUFFER_VISUALIZATION_ROUGHNESS 3
#define BUFFER_VISUALIZATION_METALNESS 4
#define BUFFER_VISUALIZATION_REFLECTANCE 5

cbuffer RootConstant : register(b0)
{
    uint buffer_visualization_mode;
};

Texture2D<float4> GBuffer0 : register(t0, UPDATE_FREQ_PER_FRAME);
Texture2D<float4> GBuffer1 : register(t1, UPDATE_FREQ_PER_FRAME);
Texture2D<float4> GBuffer2 : register(t2, UPDATE_FREQ_PER_FRAME);

float4 main(float4 position : SV_Position) : SV_Target0
{
    float3 buffer = 0;

    if (buffer_visualization_mode == BUFFER_VISUALIZATION_ALBEDO)
    {
        buffer = ApplySRGBCurve(GBuffer0[(int2)position.xy].rgb);
    }
    else if (buffer_visualization_mode == BUFFER_VISUALIZATION_WORLD_NORMAL)
    {
        float3 worldNormal = GBuffer1[(int2)position.xy].rgb;
        buffer = worldNormal * 0.5 + 0.5;
    }
    else if (buffer_visualization_mode == BUFFER_VISUALIZATION_OCCLUSION)
    {
        buffer = GBuffer2[(int2)position.xy].rrr;
    }
    else if (buffer_visualization_mode == BUFFER_VISUALIZATION_ROUGHNESS)
    {
        buffer = GBuffer2[(int2)position.xy].ggg;
    }
    else if (buffer_visualization_mode == BUFFER_VISUALIZATION_METALNESS)
    {
        buffer = GBuffer2[(int2)position.xy].bbb;
    }
    else if (buffer_visualization_mode == BUFFER_VISUALIZATION_REFLECTANCE)
    {
        buffer = GBuffer2[(int2)position.xy].aaa;
    }

    return float4(buffer, 1.0);
}
