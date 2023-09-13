#ifndef __UTILS_HLSL__
#define __UTILS_HLSL__

float luminance(float3 rgb)
{
	return dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
}

#endif // __UTILS_HLSL__