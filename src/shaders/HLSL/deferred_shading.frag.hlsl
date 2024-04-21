#define DIRECT3D12
#define STAGE_FRAG

#include "../FSL/d3d.h"

RES(SamplerState, bilinearRepeatSampler, UPDATE_FREQ_NONE, s0, binding = 1);
RES(SamplerState, bilinearClampSampler, UPDATE_FREQ_NONE, s1, binding = 2);
RES(SamplerState, pointSampler, UPDATE_FREQ_NONE, s2, binding = 3);

RES(Tex2D(float2), brdfIntegrationMap, UPDATE_FREQ_NONE, t0, binding = 4);
RES(TexCube(float4), irradianceMap, UPDATE_FREQ_NONE, t1, binding = 5);
RES(TexCube(float4), specularMap, UPDATE_FREQ_NONE, t2, binding = 6);

RES(Tex2D(float4), gBuffer0, UPDATE_FREQ_NONE, t3, binding = 7);
RES(Tex2D(float4), gBuffer1, UPDATE_FREQ_NONE, t4, binding = 8);
RES(Tex2D(float4), gBuffer2, UPDATE_FREQ_NONE, t5, binding = 9);
RES(Tex2D(float), depthBuffer, UPDATE_FREQ_NONE, t6, binding = 10);
RES(Tex2D(float), shadowDepthBuffer, UPDATE_FREQ_NONE, t7, binding = 11);

#include "pbr.hlsl"

CBUFFER(cbFrame, UPDATE_FREQ_PER_FRAME, b1, binding = 0)
{
    DATA(float4x4, projView, None);
    DATA(float4x4, projViewInverted, None);
    DATA(float4x4, lightProjView, None);
    DATA(float4x4, lightProjViewInverted, None);
    DATA(float4,   camPos,   None);
    DATA(uint,     directionalLightsBufferIndex, None);
    DATA(uint,     pointLightsBufferIndex, None);
    DATA(uint,     directionalLightsCount, None);
    DATA(uint,     pointLightsCount, None);
};

STRUCT(VsOut)
{
    DATA(float4, Position,  SV_Position);
    DATA(float2, UV, TEXCOORD0);
};

float3 getPositionFromDepth(float depth, float2 uv) {
    float x = uv.x * 2.0f - 1.0f;
    float y = (1.0f - uv.y) * 2.0f - 1.0f;
    float4 positionCS = float4(x, y, depth, 1.0f);
    float4 positionWS = mul(Get(projViewInverted), positionCS);
    return positionWS.xyz / positionWS.w;
}

float ShadowTest(float4 Pl, float2 shadowMapDimensions)
{
	// homogenous position after perspective divide
	const float3 projLSpaceCoords = Pl.xyz / Pl.w;

	// light frustum check
	if (projLSpaceCoords.x < -1.0f || projLSpaceCoords.x > 1.0f ||
		projLSpaceCoords.y < -1.0f || projLSpaceCoords.y > 1.0f ||
		projLSpaceCoords.z <  0.0f || projLSpaceCoords.z > 1.0f)
	{
		return 1.0f;
	}

	const float2 texelSize = 1.0f / (shadowMapDimensions);

	// clip space [-1, 1] --> texture space [0, 1]
	const float2 shadowTexCoords = float2(0.5f, 0.5f) + projLSpaceCoords.xy * float2(0.5f, -0.5f);	// invert Y

	//const float BIAS = pcfTestLightData.depthBias * tan(acos(pcfTestLightData.NdotL));
	const float BIAS = 0.0001f;
	const float pxDepthInLSpace = projLSpaceCoords.z;

	float shadow = 0.0f;
	const int rowHalfSize = 2;

	// PCF
	for (int x = -rowHalfSize; x <= rowHalfSize; ++x)
	{
		for (int y = -rowHalfSize; y <= rowHalfSize; ++y)
		{
			float2 texelOffset = float2(x, y) * texelSize;
			float closestDepthInLSpace = SampleLvlTex2D(Get(shadowDepthBuffer), Get(pointSampler), shadowTexCoords + texelOffset, 0).x;

			// depth check
			shadow += (pxDepthInLSpace + BIAS < closestDepthInLSpace) ? 1.0f : 0.0f;
		}
	}

	shadow /= (rowHalfSize * 2 + 1) * (rowHalfSize * 2 + 1);
	return 1.0 - shadow;
}


float4 PS_MAIN( VsOut Input) : SV_TARGET0 {
    INIT_MAIN;

    float4 baseColor  = SampleLvlTex2D(Get(gBuffer0), Get(bilinearClampSampler), Input.UV, 0);
    if (baseColor.a <= 0)
    {
        RETURN(float4(0.0, 0.0, 0.0, 0.0));
    }

    float3 N = normalize(SampleLvlTex2D(Get(gBuffer1), Get(bilinearClampSampler), Input.UV, 0).rgb * 2.0f - 1.0f);
    float3 armSample = SampleLvlTex2D(Get(gBuffer2), Get(bilinearClampSampler), Input.UV, 0).rgb;
    float depth  = SampleLvlTex2D(Get(depthBuffer), Get(bilinearClampSampler), Input.UV, 0).r;

    const float3 P = getPositionFromDepth(depth, Input.UV);
    const float3 V = normalize(Get(camPos).xyz - P);

    float4 positionLightSpace = mul(Get(lightProjView), float4(P, 1.0f));
    float shadow = ShadowTest(positionLightSpace, 2048.0f);

    float metalness = armSample.b;
    float roughness = armSample.g;
    if (roughness < 0.04) roughness = 0.04;

    float3 Lo = float3(0.0f, 0.0f, 0.0f);

    // Point Lights
    uint i;
    ByteAddressBuffer pointLightsBuffer = ResourceDescriptorHeap[Get(pointLightsBufferIndex)];
    for (i = 0; i < Get(pointLightsCount); ++i) {
        const PointLight pointLight = pointLightsBuffer.Load<PointLight>(i * sizeof(PointLight));
        const float3 Pl = pointLight.positionAndRadius.xyz;
        const float  radius = pointLight.positionAndRadius.w;
        const float3 L = normalize(Pl - P);
        const float  NdotL = max(dot(N, L), 0.0f);
        const float  distance = length(Pl - P);
        const float  distanceByRadius = 1.0f - pow((distance / radius), 4);
        const float  clamped = pow(saturate(distanceByRadius), 2.0f);
        const float  attenuation = clamped / (distance * distance + 1.0f);

        const float3 color = pointLight.colorAndIntensity.rgb;
        const float  intensity = pointLight.colorAndIntensity.a;
        const float3 radiance = color * intensity * attenuation;

        Lo += BRDF(N, V, L, baseColor.rgb, roughness, metalness) * radiance * NdotL * shadow;
    }

    // Directional Lights
    ByteAddressBuffer directionalLightsBuffer = ResourceDescriptorHeap[Get(directionalLightsBufferIndex)];
    for (i = 0; i < Get(directionalLightsCount); ++i)
    {
        const DirectionalLight directionalLight = directionalLightsBuffer.Load<DirectionalLight>(i * sizeof(DirectionalLight));
        const float3 L = directionalLight.directionAndShadowMap.xyz;
        const float  NdotL = max(dot(N, L), 0.0f);
        const float3 color = directionalLight.colorAndIntensity.rgb;
        const float  intensity = directionalLight.colorAndIntensity.a;
        const float3 radiance = color * intensity;

        Lo += BRDF(N, V, L, baseColor.rgb, roughness, metalness) * radiance * NdotL * shadow;
    }

    // IBL (Environment Light)
    float environmentLightIntensity = 0.15f;
    Lo += EnvironmentBRDF(N, V, baseColor.rgb, roughness, metalness) * environmentLightIntensity;

    RETURN(float4(Lo, 1.0f));
}
