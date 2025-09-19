#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

GBufferOutput main(VertexAttribute vertex, PrimitiveAttribute primitive)
{
    GBufferOutput Out;
    Out.GBuffer0 = float4(primitive.candidate_index, primitive.primitive_id, 0.0f, 1.0f);
    Out.GBuffer1 = float4(0.0f, 1.0f, 0.0f, 1.0f);
    Out.GBuffer2 = float4(1.0f, 0.04f, 0.0f, 0.5f);

    return Out;
}