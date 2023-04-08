#ifndef __PBR_HLSLI__
#define __PBR_HLSLI__

#include "common.hlsli"

#define PI 3.14159265f
#define EPSILON 1e-6f

// Appoximation of joint Smith term for GGX
// [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
inline float V_SmithJointApprox(float a, float n_dot_v, float n_dot_l)
{
    float Vis_SmithV = n_dot_l * (n_dot_v * (1 - a) + a);
    float Vis_SmithL = n_dot_v * (n_dot_l * (1 - a) + a);
    return saturate_16(0.5 * rcp(Vis_SmithV + Vis_SmithL));
}

// GGX / Trowbridge-Reitz
// [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
float D_GGX(float roughness_alpha_squared, float n_dot_h)
{
    float f = (n_dot_h * roughness_alpha_squared - n_dot_h) * n_dot_h + 1.0f;
    return roughness_alpha_squared / (PI * f * f + FLT_MIN);
}

float3 F_Schlick(const float3 f0, float f90, float v_dot_h)
{
    // Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
    return f0 + (f90 - f0) * pow(1.0 - v_dot_h, 5.0);
}

float3 F_Schlick(const float3 f0, float v_dot_h)
{
    float f = pow(1.0 - v_dot_h, 5.0);
    return f + f0 * (1.0 - f);
}

float3 computeDiffuseEnergy(float3 F, float metallic)
{
    float3 kS = F;          // The energy of light that gets reflected - Equal to Fresnel
    float3 kD = 1.0f - kS;  // Remaining energy, light that gets refracted
    kD *= 1.0f - metallic;  // Multiply kD by the inverse metalness such that only non-metals have diffuse lighting
    
    return kD;
}

// Gotanda 2012, "Beyond a Simple Physically Based Blinn-Phong Model in Real-Time"
float3 BRDF_Diffuse_OrenNayar(float3 albedo, float roughness, float roughness_alpha_squared, float v_dot_h, float n_dot_l, float n_dot_v)
{
    float v_dot_l = 2 * v_dot_h * v_dot_h - 1;
    float cosri = v_dot_l - n_dot_v * n_dot_l;
    float c1 = 1 - 0.5 * roughness_alpha_squared / (roughness_alpha_squared + 0.33);
    float c2 = 0.45 * roughness_alpha_squared / (roughness_alpha_squared + 0.09) * cosri * (cosri >= 0 ? rcp(max(n_dot_l, n_dot_v + 0.0001f)) : 1);
    return albedo / PI * (c1 + c2) * (1 + roughness * 0.5);
}

float3 BRDF_Specular_Isotropic(float roughness_alpha, float roughness_alpha_squared, float3 F0, float metallic, float n_dot_v, float n_dot_l, float n_dot_h, float v_dot_h, inout float3 diffuse_energy, inout float3 specular_energy)
{
    float  V = V_SmithJointApprox(roughness_alpha, n_dot_v, n_dot_l);
    float  D = D_GGX(roughness_alpha_squared, n_dot_h);
    float3 F = F_Schlick(F0, v_dot_h);

    diffuse_energy  *= computeDiffuseEnergy(F, metallic);
    specular_energy *= F;

    return D * V * F;
}

#endif // __PBR_HLSLI__