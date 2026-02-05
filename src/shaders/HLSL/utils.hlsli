#ifndef _UTILS_H
#define _UTILS_H

float pow5(float value)
{
	return (value * value) * (value * value) * value;
}

float inverseLerp(float a, float b, float value)
{
	return (value - a) / (b - a);
}

float3 inverseLerp3(float3 a, float3 b, float3 value)
{
	return float3(
		inverseLerp(a.x, b.x, value.x),
		inverseLerp(a.x, b.y, value.y),
		inverseLerp(a.x, b.y, value.z));
}

float3 ReconstructNormal(float4 sampleNormal, float intensity)
{
	float3 tangentNormal;
	tangentNormal.xy = (sampleNormal.rg * 2.0f - 1.0f) * intensity;
	tangentNormal.z = sqrt(saturate(1.0f - dot(tangentNormal.xy, tangentNormal.xy)));
	return tangentNormal;
}

float3 NormalBlend(float3 normal1, float3 normal2)
{
	return normalize(float3(normal1.xy + normal2.xy, normal1.z * normal2.z));
}

float3x3 ComputeTBN(float3 normal, float4 tangent)
{
	float3 bitangent = cross(normal, tangent.xyz) * tangent.w;
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

	float invScale = rsqrt(max(0.0001f, max(dot(T, T), dot(B, B))));

	float3x3 TBN = make_f3x3_rows(T * invScale, B * invScale, N);
	return normalize(mul(tangentNormal, TBN));
}

bool IsNaN(float x)
{
	return (asuint(x) & 0x7fffffff) > 0x7f800000;
}

bool IsNaN(float3 x)
{
	return IsNaN(x.r) || IsNaN(x.g) || IsNaN(x.b);
}

//  ██████╗ ██████╗ ██╗      ██████╗ ██████╗     ██╗   ██╗████████╗██╗██╗     ██╗██╗████████╗███████╗███████╗
// ██╔════╝██╔═══██╗██║     ██╔═══██╗██╔══██╗    ██║   ██║╚══██╔══╝██║██║     ██║██║╚══██╔══╝██╔════╝██╔════╝
// ██║     ██║   ██║██║     ██║   ██║██████╔╝    ██║   ██║   ██║   ██║██║     ██║██║   ██║   █████╗  ███████╗
// ██║     ██║   ██║██║     ██║   ██║██╔══██╗    ██║   ██║   ██║   ██║██║     ██║██║   ██║   ██╔══╝  ╚════██║
// ╚██████╗╚██████╔╝███████╗╚██████╔╝██║  ██║    ╚██████╔╝   ██║   ██║███████╗██║██║   ██║   ███████╗███████║
//  ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝     ╚═════╝    ╚═╝   ╚═╝╚══════╝╚═╝╚═╝   ╚═╝   ╚══════╝╚══════╝

INLINE float sRGBToLinear(float s)
{
	if (s <= 0.04045f)
		return s / 12.92f;
	else
		return pow((s + 0.055) / 1.055, 2.4);
}

INLINE float LinearTosRGB(float l)
{
	if (l < 0.0031308f)
		return l * 12.92f;
	else
		return 1.055 * pow(l, 1.0f / 2.4f) - 0.055f;
}

INLINE float3 sRGBToLinear_Float3(float3 s)
{
	return float3(
		sRGBToLinear(s.r),
		sRGBToLinear(s.g),
		sRGBToLinear(s.b));
}

INLINE float3 LinearTosRGB_Float3(float3 l)
{
	return float3(
		LinearTosRGB(l.r),
		LinearTosRGB(l.g),
		LinearTosRGB(l.b));
}

float Luminance(float3 linear_color)
{
	return dot(linear_color, float3(0.2126729f, 0.7151522f, 0.0721750f));
}

float3 RgbToHsv(float3 c)
{
	const float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
	float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	const float e = 1.0e-4;
	return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float3 HsvToRgb(float3 c)
{
	const float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
}

float RotateHue(float value, float low, float hi)
{
	return (value < low) ? value + hi : ((value > hi) ? value - hi : value);
}

// https://www.arri.com/resource/blob/31918/66f56e6abb6e5b6553929edf9aa7483e/2017-03-alexa-logc-curve-in-vfx-data.pdf
struct LogCParameters
{
	float cut;
	float a;
	float b;
	float c;
	float d;
	float e;
	float f;
};

static const LogCParameters k_log_c_paramenters = {
	0.011361, // cut
	5.555556, // a
	0.047996, // b
	0.244161, // c
	0.386036, // d
	5.301883, // e
	0.092819  // f
};

float LinearToLogC_float(float value)
{
	if (value > k_log_c_paramenters.cut)
	{
		return k_log_c_paramenters.c * log10(max(k_log_c_paramenters.a * value + k_log_c_paramenters.b, 0.0)) + k_log_c_paramenters.d;
	}
	else
	{
		return k_log_c_paramenters.e * value + k_log_c_paramenters.f;
	}
}

float LogCToLinear_float(float value)
{
	if (value > k_log_c_paramenters.e * k_log_c_paramenters.cut + k_log_c_paramenters.f)
	{
		return (pow(10.0, (value - k_log_c_paramenters.d) / k_log_c_paramenters.c) - k_log_c_paramenters.b) / k_log_c_paramenters.a;
	}
	else
	{
		return (value - k_log_c_paramenters.f) / k_log_c_paramenters.e;
	}
}

float3 LinearToLogC(float3 color)
{
	return float3(
		LinearToLogC_float(color.r),
		LinearToLogC_float(color.g),
		LinearToLogC_float(color.b));
}

float3 LogCToLinear(float3 color)
{
	return float3(
		LogCToLinear_float(color.r),
		LogCToLinear_float(color.g),
		LogCToLinear_float(color.b));
}

static const uint INVALID_TEXTURE_INDEX = 0xFFFFFFFF;

bool hasValidTexture(uint textureIndex)
{
	return textureIndex != INVALID_TEXTURE_INDEX;
}

float4 BlendOverlay(float4 base, float4 blend, float opacity)
{
	float4 result;
	float4 result1 = 1.0 - 2.0 * (1.0 - base) * (1.0 - blend);
	float4 result2 = 2.0 * base * blend;
	float4 zeroOrOne = step(base, 0.5);
	result = result2 * zeroOrOne + (1 - zeroOrOne) * result1;
	return lerp(base, result, opacity);
}

float4 BlendDodge(float4 base, float4 blend, float opacity)
{
	float4 result = base / (1.0 - blend);
	return lerp(base, result, opacity);
}

#endif // _UTILS_H