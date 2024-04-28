// Adapted from https://github.com/john-chapman/im3d/blob/master/examples/DirectX11/im3d.hlsl
#ifndef _IM3D_HLSL
#define _IM3D_HLSL

#include "../FSL/d3d.h"
#include "../FSL/ShaderUtilities.h.fsl"

struct VS_OUTPUT
{
	linear        float4 m_position     : SV_POSITION;
	linear        float4 m_color        : COLOR;
	linear        float2 m_uv           : TEXCOORD;
	noperspective float  m_size         : SIZE;
	noperspective float  m_edgeDistance : EDGE_DISTANCE;
};

#define kAntialiasing 2.0

#endif // _IM3D_HLSL