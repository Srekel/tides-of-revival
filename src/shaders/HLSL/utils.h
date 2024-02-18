#ifndef _UTILS_H
#define _UTILS_H

float3 ReconstructNormal(float4 sampleNormal, float intensity)
{
	float3 tangentNormal;
	tangentNormal.xy = (sampleNormal.rg * 2 - 1) * intensity;
	tangentNormal.z = sqrt(1 - saturate(dot(tangentNormal.xy, tangentNormal.xy)));
	return tangentNormal;
}

INLINE float3 UnpackNormals(float2 uv, float3 viewDirection, Tex2D(float4) normalMap, SamplerState samplerState, float3 normal, float intensity)
{
	float3 tangentNormal = ReconstructNormal(SampleTex2D(normalMap, samplerState, uv), intensity);

	float3 dPdx = ddx(viewDirection);
	float3 dPdy = ddy(viewDirection);
	float2 dUVdx = ddx(uv);
	float2 dUVdy = ddy(uv);

	float3 N = normalize(normal);
	float3 crossPdyN = cross(dPdy, N);
	float3 crossNPdx = cross(N, dPdx);

	float3 T = crossPdyN * dUVdx.x + crossNPdx * dUVdy.x;
	float3 B = crossPdyN * dUVdx.y + crossNPdx * dUVdy.y;

	float invScale = rsqrt(max(dot(T, T), dot(B, B)));

	float3x3 TBN = make_f3x3_rows(T * invScale, B * invScale, N);
	return normalize(mul(tangentNormal, TBN));
}

#endif // _UTILS_H