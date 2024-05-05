#ifndef _WIND_H
#define _WIND_H

#ifndef WIND_CBUFFER_REG
#define WIND_CBUFFER_REG b2
#endif

#ifndef WIND_CBUFFER_BINDING
#define WIND_CBUFFER_BINDING 1
#endif

#define FLT_EPSILON 1.192092896e-07

CBUFFER(cbWind, UPDATE_FREQ_PER_FRAME, WIND_CBUFFER_REG, binding = WIND_CBUFFER_BINDING)
{
	DATA(float4, windWorldDirectionAndSpeed, None);
	DATA(float, windFlexNoiseScale, None);
	DATA(float, windTurbulence, None);
	DATA(float, windGustSpeed, None);
	DATA(float, windGustScale, None);
	DATA(float, windGustWorldScale, None);
    DATA(uint, windNoiseTextureIndex, None);
    DATA(uint, windGustTextureIndex, None);
};

float PositivePow(float base, float power)
{
    return pow(max(abs(base), float(FLT_EPSILON)), power);
}

float AttenuateTrunk(float x, float s)
{
    float r = (x / s);
    return PositivePow(r, 1 / s);
}

float3 Rotate(float3 pivot, float3 position, float3 rotationAxis, float angle)
{
    rotationAxis = normalize(rotationAxis);
    float3 cpa = pivot + rotationAxis * dot(rotationAxis, position - pivot);
    return cpa + ((position - cpa) * cos(angle) + cross(rotationAxis, (position - cpa)) * sin(angle));
}

struct WindData
{
    float3 Direction;
    float Strength;
    float3 Gust;
};

float3 texNoise(float3 worldPos, float LOD)
{
    Texture2D noiseMap = ResourceDescriptorHeap[Get(windNoiseTextureIndex)];
    return SampleLvlTex2D(noiseMap, Get(bilinearRepeatSampler), worldPos.xz, LOD).xyz - 0.5;
}

float texGust(float3 worldPos, float LOD)
{
    Texture2D gustMap = ResourceDescriptorHeap[Get(windGustTextureIndex)];
    return SampleLvlTex2D(gustMap, Get(bilinearRepeatSampler), worldPos.xz, LOD).x;
}

WindData GetAnalyticalWind(float3 worldPosition, float3 pivotPosition, float drag, float initialBend, float time)
{
    WindData result;

    float3 normalizedDir = normalize(Get(windWorldDirectionAndSpeed).xyz);
    float3 worldOffset = float3(1, 0, 0) * Get(windWorldDirectionAndSpeed).w * time;
    float3 gustWorldOffset = float3(1, 0, 0) * Get(windGustSpeed) * time;

    // Trunk noise is base wind + gusts + noise
    float3 trunk = float3(0, 0, 0);
    if (Get(windWorldDirectionAndSpeed).w > 0.0 || Get(windTurbulence) > 0.0)
    {
        trunk = texNoise((pivotPosition - worldOffset) * Get(windFlexNoiseScale), 3);
    }

    float gust = 0.0;
    if (Get(windGustSpeed) > 0.0)
    {
        gust = texGust((pivotPosition - gustWorldOffset) * Get(windGustWorldScale), 3);
        gust = pow(gust, 2) * Get(windGustScale);
    }

    float3 trunkNoise = (
        (normalizedDir * Get(windWorldDirectionAndSpeed.w))
        + (gust * normalizedDir * Get(windGustSpeed))
        + (trunk * Get(windTurbulence))
    ) * drag;

    float3 dir = trunkNoise;
    float flex = length(trunkNoise) + initialBend;

    result.Direction = dir;
    result.Strength = flex;
    result.Gust = (gust * normalizedDir * Get(windGustSpeed)) + (trunk * Get(windTurbulence));

    return result;
}

void ApplyWindDisplacement(inout float3 positionWS, inout WindData windData, float3 normalWS, float3 rootWP, float stifness, float drag, float initialBend, float time)
{
    WindData wind = GetAnalyticalWind(positionWS, rootWP, drag, initialBend, time);

    if (wind.Strength > 0.0)
    {
        float att = AttenuateTrunk(distance(positionWS, rootWP), stifness);
        float3 rotAxis = cross(float3(0, 1, 0), wind.Direction);

        positionWS = Rotate(rootWP, positionWS, rotAxis, wind.Strength * 0.001 * att);
    }

    windData = wind;
}

#endif // _WIND_H