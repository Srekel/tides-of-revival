#ifndef _FONTSTASH_RESOURCES_H
#define _FONTSTASH_RESOURCES_H

#include "../FSL/d3d.h"

CBUFFER(uniformBlock_rootcbv, UPDATE_FREQ_NONE, b1, binding = 1)
{
#if FT_MULTIVIEW
	DATA(float4x4, mvp[VR_MULTIVIEW_COUNT], None);
#else
	DATA(float4x4, mvp, None);
#endif
};

RES(Tex2D(float4), uTex0, UPDATE_FREQ_NONE, t2, binding = 2);
RES(SamplerState, uSampler0, UPDATE_FREQ_NONE, s3, binding = 3);

PUSH_CONSTANT(uRootConstants, b0)
{
	DATA(float4, color, None);
	DATA(float2, scaleBias, None);
};

#endif // _FONTSTASH_RESOURCES_H