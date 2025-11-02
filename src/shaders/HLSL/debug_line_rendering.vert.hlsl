#include "debug_line_rendering.hlsli"

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    output.color = input.color;
    output.position = mul(float4(input.position, 1.0), g_DebugFrame.viewProj);

    return output;
}
