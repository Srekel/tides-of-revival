#ifndef _UTILS_H
#define _UTILS_H

float3 ReconstructNormal(float4 sampleNormal, float intensity)
{
	float3 tangentNormal;
	tangentNormal.xy = (sampleNormal.rg * 2.0f - 1.0f) * intensity;
	tangentNormal.z = sqrt(1.0f - saturate(dot(tangentNormal.xy, tangentNormal.xy)));
	return tangentNormal;
}

float3x3 ComputeTBN(float3 normal, float4 tangent)
{
	normal = normalize(normal);
	tangent.xyz = normalize(tangent.xyz);
	float3 bitangent = cross(normal, tangent.xyz) * -tangent.w;
	return float3x3(tangent.xyz, bitangent, normal);
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

INLINE float sRGBToLinear(float s)
{
	if (s <= 0.04045f) return s / 12.92f;
	else return pow((s + 0.055) / 1.055, 2.4);
}

INLINE float LinearTosRGB(float l)
{
	if (l < 0.0031308f) return l * 12.92f;
	else return 1.055 * pow(l, 1.0f / 2.4f) - 0.055f;
}

INLINE float3 sRGBToLinear_Float3(float3 s) {
	return float3(
		sRGBToLinear(s.r),
		sRGBToLinear(s.g),
		sRGBToLinear(s.b)
	);
}

INLINE float3 LinearTosRGB_Float3(float3 l) {
	return float3(
		LinearTosRGB(l.r),
		LinearTosRGB(l.g),
		LinearTosRGB(l.b)
	);
}

#endif // _UTILS_H