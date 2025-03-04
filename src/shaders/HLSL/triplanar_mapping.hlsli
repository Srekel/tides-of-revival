// This file is based on the "Normal Mapping for a Triplanar Shader" article by Ben Golus
// https://bgolus.medium.com/normal-mapping-for-a-triplanar-shader-10bf39dca05a
#ifndef _TRIPLANAR_MAPPING_HLSLI
#define _TRIPLANAR_MAPPING_HLSLI

#define TRIPLANAR_METHOD_SWIZZLE 0
#define TRIPLANAR_METHOD_UDN_BLEND 1
#define TRIPLANAR_METHOD_WHITEOUT_BLEND 2
#define TRIPLANAR_METHOD_RNM 3

#define TRIPLANAR_METHOD TRIPLANAR_METHOD_RNM

// Reoriented Normal Mapping for Unity3d
// http://discourse.selfshadow.com/t/blending-in-detail/21/18

float3 rnmBlendUnpacked(float3 n1, float3 n2)
{
    n1 += float3(0, 0, 1);
    n2 *= float3(-1, -1, 1);
    return n1 * dot(n1, n2) / n1.z - n2;
}

float3 Triplanar_GenerateWeights(float3 worldNormal)
{
    float3 weights = pow(abs(worldNormal), 4);
    weights /= max(dot(weights, float3(1, 1, 1)), 0.0001);

    return weights;
}

float3 Triplanar_Blend(float3 tangentNormalX, float3 tangentNormalY, float3 tangentNormalZ, float3 worldNormal)
{
    float3 triblend = Triplanar_GenerateWeights(worldNormal);

#if TRIPLANAR_METHOD == TRIPLANAR_METHOD_SWIZZLE
    // Basic Swizzle Method

    // Get the sign (-1 or 1) of the surface normal
    float3 axisSign = sign(worldNormal);
    // Flip tangent normal Z to account for surface normal facing
    tangentNormalX.z *= axisSign.x;
    tangentNormalY.z *= axisSign.y;
    tangentNormalZ.z *= axisSign.z;
#elif TRIPLANAR_METHOD == TRIPLANAR_METHOD_UDN_BLEND
    // UDN Blend

    // Swizzle world normals into tangent space and apply UDN blend.
    // These should get normalized, but it's very a minor visual
    // difference to skip it until after the blend.
    tangentNormalX = float3(tangentNormalX.xy + worldNormal.zy, worldNormal.x);
    tangentNormalY = float3(tangentNormalY.xy + worldNormal.xz, worldNormal.y);
    tangentNormalZ = float3(tangentNormalZ.xy + worldNormal.xy, worldNormal.z);
#elif TRIPLANAR_METHOD == TRIPLANAR_METHOD_WHITEOUT_BLEND
    // Whiteout blend

    // Swizzle world normals into tangent space and apply Whiteout blend
    tangentNormalX = float3(tangentNormalX.xy + worldNormal.zy, abs(tangentNormalX.z) * worldNormal.x);
    tangentNormalY = float3(tangentNormalY.xy + worldNormal.xz, abs(tangentNormalY.z) * worldNormal.y);
    tangentNormalZ = float3(tangentNormalZ.xy + worldNormal.xy, abs(tangentNormalZ.z) * worldNormal.z);
#elif TRIPLANAR_METHOD == TRIPLANAR_METHOD_RNM
    // Reoriented Normal Mapping

    // Get absolute value of normal to ensure positive tangent "z" for blend
    float3 absVertNormal = abs(worldNormal);

    // Swizzle world normals to match tangent space and apply RNM blend
    tangentNormalX = rnmBlendUnpacked(float3(worldNormal.zy, absVertNormal.x), tangentNormalX);
    tangentNormalY = rnmBlendUnpacked(float3(worldNormal.xz, absVertNormal.y), tangentNormalY);
    tangentNormalZ = rnmBlendUnpacked(float3(worldNormal.xy, absVertNormal.z), tangentNormalZ);

    // Get the sign (-1 or 1) of the surface normal
    float3 axisSign = sign(worldNormal);
    // Reapply sign to Z
    tangentNormalX.z *= axisSign.x;
    tangentNormalY.z *= axisSign.y;
    tangentNormalZ.z *= axisSign.z;
#endif

    // Swizzle tangent normals to match world orientation and tri-blend
    return normalize(tangentNormalX.zyx * triblend.x +
                     tangentNormalY.xzy * triblend.y +
                     tangentNormalZ.xyz * triblend.z);
}

float3 Triplanar_SampleNormalMap(Texture2D normalMap, SamplerState samplerState, float3 worldPosition, float3 worldNormal, float normalIntensity)
{
    // Triplanar UVs
    float2 uvX = worldPosition.zy; // x facing plane
    float2 uvY = worldPosition.xz; // y facing plane
    float2 uvZ = worldPosition.xy; // z facing plane
    // Tangent space normals
    float3 tangentNormalX = ReconstructNormal(SampleTex2D(normalMap, samplerState, uvX), normalIntensity);
    float3 tangentNormalY = ReconstructNormal(SampleTex2D(normalMap, samplerState, uvY), normalIntensity);
    float3 tangentNormalZ = ReconstructNormal(SampleTex2D(normalMap, samplerState, uvZ), normalIntensity);

    return Triplanar_Blend(tangentNormalX, tangentNormalY, tangentNormalZ, worldNormal);
}

#endif // _TRIPLANAR_MAPPING_HLSLI