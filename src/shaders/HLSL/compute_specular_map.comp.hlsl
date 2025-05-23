/*
 * Copyright (c) 2017-2024 The Forge Interactive Inc.
 *
 * This file is part of The-Forge
 * (see https://github.com/ConfettiFX/The-Forge).
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
*/

#define DIRECT3D12
#define STAGE_COMP

#include "../FSL/d3d.h"

// USERMACRO: IMPORTANCE_SAMPLE_COUNT [64,128,256,1024]
#ifndef IMPORTANCE_SAMPLE_COUNT
	#define IMPORTANCE_SAMPLE_COUNT 1024
#endif

STATIC float Pi = 3.14159265359;
STATIC int SampleCount = IMPORTANCE_SAMPLE_COUNT;

PUSH_CONSTANT(RootConstant, b0)
{
	DATA(uint, pcMipSize, None);
	DATA(float, pcRoughness, None);
};

RES(TexCube(float4), srcTexture, UPDATE_FREQ_NONE, t1, binding = 1);
RES(WTex2DArray(float4), dstTexture, UPDATE_FREQ_PER_DRAW, u2, binding = 2);
RES(SamplerState, g_skybox_sampler, UPDATE_FREQ_NONE, s3, binding = 3);

float RadicalInverse_VdC(uint bits)
{
	bits = (bits << 16u) | (bits >> 16u);
	bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
	bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
	bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
	bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
	return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

float2 Hammersley(uint i, uint N)
{
	return float2(float(i) / float(N), RadicalInverse_VdC(i));
}

float DistributionGGX(float3 N, float3 H, float roughness)
{
	float a = roughness * roughness;
	float a2 = a * a;
	float NdotH = max(dot(N, H), 0.0);
	float NdotH2 = NdotH * NdotH;

	float nom = a2;
	float denom = (NdotH2 * (a2 - 1.0) + 1.0);
	denom = Pi * denom * denom;

	return nom / denom;
}

float3 ImportanceSampleGGX(float2 Xi, float3 N, float roughness)
{
	float a = roughness * roughness;

	float phi = 2.0 * Pi * Xi.x;
	float cosTheta = sqrt(saturate((1.0 - Xi.y) / (1.0 + (a*a - 1.0) * Xi.y)));
	float sinTheta = sqrt(saturate(1.0 - cosTheta * cosTheta));

	// from spherical coordinates to cartesian coordinates
	float3 H;
	H.x = cos(phi) * sinTheta;
	H.y = sin(phi) * sinTheta;
	H.z = cosTheta;

	// from tangent-space vector to world-space sample vector
	float3 up = abs(N.z) < 0.999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
	float3 tangent = normalize(cross(up, N));
	float3 bitangent = cross(N, tangent);

	float3 sampleVec = tangent * H.x + bitangent * H.y + N * H.z;
	return normalize(sampleVec);
}

NUM_THREADS(16, 16, 1)
void CS_MAIN(uint3 DTid : SV_DispatchThreadID)
{
	INIT_MAIN;
	uint3 threadPos = DTid;

	float mipRoughness = Get(pcRoughness);
	uint mipSize = Get(pcMipSize);

	if (threadPos.x >= mipSize || threadPos.y >= mipSize) return;

	float2 texcoords = float2(float(threadPos.x + 0.5) / mipSize, float(threadPos.y + 0.5) / mipSize);

	float3 sphereDir = f3(1);

	if (threadPos.z <= 0)
		sphereDir = normalize(float3(0.5, -(texcoords.y - 0.5), -(texcoords.x - 0.5)));
	else if (threadPos.z <= 1)
		sphereDir = normalize(float3(-0.5, -(texcoords.y - 0.5), texcoords.x - 0.5));
	else if (threadPos.z <= 2)
		sphereDir = normalize(float3(texcoords.x - 0.5, 0.5, texcoords.y - 0.5));
	else if (threadPos.z <= 3)
		sphereDir = normalize(float3(texcoords.x - 0.5, -0.5, -(texcoords.y - 0.5)));
	else if (threadPos.z <= 4)
		sphereDir = normalize(float3(texcoords.x - 0.5, -(texcoords.y - 0.5), 0.5));
	else if (threadPos.z <= 5)
		sphereDir = normalize(float3(-(texcoords.x - 0.5), -(texcoords.y - 0.5), -0.5));

	float3 N = sphereDir;
	float3 R = N;
	float3 V = R;

	float totalWeight = 0.0;
	float4 prefilteredColor = float4(0.0, 0.0, 0.0, 0.0);

	float2 dim = float2(GetDimensions(Get(srcTexture), Get(g_skybox_sampler)));
	float srcTextureSize = max(dim[0], dim[1]);

	for (int i = 0; i < SampleCount; ++i)
	{
		float2 Xi = Hammersley(i, SampleCount);
		float3 H = ImportanceSampleGGX(Xi, N, mipRoughness);
		float3 L = normalize(2.0 * dot(V, H) * H - V);

		float NdotL = max(dot(N, L), 0.0);
		if (NdotL > 0.0)
		{
			// sample from the environment's mip level based on roughness/pdf
			float D = DistributionGGX(N, H, mipRoughness);
			float NdotH = max(dot(N, H), 0.0);
			float HdotV = max(dot(H, V), 0.0);
			float pdf = D * NdotH / (4.0 * HdotV) + 0.0001;

			float saTexel = 4.0 * Pi / (6.0 * srcTextureSize * srcTextureSize);
			float saSample = 1.0 / (float(SampleCount) * pdf + 0.0001);

			float mipLevel = mipRoughness == 0.0 ? 0.0 : max(0.5 * log2(saSample / saTexel) + 1.0f, 0.0f);

			prefilteredColor += SampleLvlTexCube(Get(srcTexture), Get(g_skybox_sampler), L, mipLevel) * NdotL;

			totalWeight += NdotL;
		}
	}

	prefilteredColor = prefilteredColor / totalWeight;
	Write3D(Get(dstTexture), threadPos.xyz, prefilteredColor);
}
