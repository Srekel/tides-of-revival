// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere
#pragma once

#include "common.hlsli"

#define PI 3.1415926535897932384626433832795f

// TODO(gmodarelli): Remove unused members if any
cbuffer SkyAtmosphereBuffer : register(b1, UPDATE_FREQ_PER_FRAME)
{
	//
	// From AtmosphereParameters
	//

	float3	solar_irradiance;
	float	sun_angular_radius;

	float3	absorption_extinction;
	float	mu_s_min;

	float3	rayleigh_scattering;
	float	mie_phase_function_g;

	float3	mie_scattering;
	float	bottom_radius;

	float3	mie_extinction;
	float	top_radius;

	float3	mie_absorption;
	float	pad00;

	float3	ground_albedo;
	float   pad0;

	float4 rayleigh_density[3];
	float4 mie_density[3];
	float4 absorption_density[3];

	//
	// Add generated static header constant
	//

	int transmittance_texture_width;
	int transmittance_texture_height;
	int irradiance_texture_width;
	int irradiance_texture_height;

	int scattering_texture_r_size;
	int scattering_texture_mu_size;
	int scattering_texture_mu_s_size;
	int scattering_texture_nu_size;

	float3 sky_spectral_radiance_to_luminance;
	float  pad3;
	float3 sun_spectral_radiance_to_luminance;
	float  pad4;

	//
	// Other globals
	//
	float4x4 sky_view_proj_mat;
	float4x4 sky_inv_view_proj_mat;
	float4x4 sky_inv_proj_mat;
	float4x4 sky_inv_view_mat;
	float4x4 shadowmap_view_proj_mat;

	float3 camera;
	float  pad5;
	float3 sun_direction;
	float  pad6;
	float3 view_ray;
	float  pad7;

	float multiple_scattering_factor;
	float multi_scattering_LUT_res;
	float pad9;
	float pad10;
};

struct AtmosphereParameters
{
	// Radius of the planet (center to ground)
	float bottom_radius;
	// Maximum considered atmosphere height (center to atmosphere top)
	float top_radius;

	// Rayleigh scattering exponential distribution scale in the atmosphere
	float rayleigh_density_exp_scale;
	// Rayleigh scattering coefficients
	float3 rayleigh_scattering;

	// Mie scattering exponential distribution scale in the atmosphere
	float mie_density_exp_scale;
	// Mie scattering coefficients
	float3 mie_scattering;
	// Mie extinction coefficients
	float3 mie_extinction;
	// Mie absorption coefficients
	float3 mie_absorption;
	// Mie phase function excentricity
	float mie_phase_g;

	// Another medium type in the atmosphere
	float absorption_density_0_layer_width;
	float absorption_density_0_constant_term;
	float absorption_density_0_linear_term;
	float absorption_density_1_constant_term;
	float absorption_density_1_linear_term;
	// This other medium only absorb light, e.g. useful to represent ozone in the earth atmosphere
	float3 absorption_extinction;

	// The albedo of the ground.
	float3 ground_albedo;
};

AtmosphereParameters GetAtmosphereParameters()
{
	AtmosphereParameters parameters;
	parameters.absorption_extinction = absorption_extinction;

	// Traslation from Bruneton2017 parameterisation.
	parameters.rayleigh_density_exp_scale = rayleigh_density[1].w;
	parameters.mie_density_exp_scale = mie_density[1].w;
	parameters.absorption_density_0_layer_width = absorption_density[0].x;
	parameters.absorption_density_0_constant_term = absorption_density[1].x;
	parameters.absorption_density_0_linear_term = absorption_density[0].w;
	parameters.absorption_density_1_constant_term = absorption_density[2].y;
	parameters.absorption_density_1_linear_term = absorption_density[2].x;

	parameters.mie_phase_g = mie_phase_function_g;
	parameters.rayleigh_scattering = rayleigh_scattering;
	parameters.mie_scattering = mie_scattering;
	parameters.mie_absorption = mie_absorption;
	parameters.mie_extinction = mie_extinction;
	parameters.ground_albedo = ground_albedo;
	parameters.bottom_radius = bottom_radius;
	parameters.top_radius = top_radius;
	return parameters;
}

// - r0: ray origin
// - rd: normalized ray direction
// - s0: sphere center
// - sR: sphere radius
// - Returns distance from r0 to first intersecion with sphere,
//   or -1.0 if no intersection.
float RaySphereIntersectNearest(float3 r0, float3 rd, float3 s0, float sR)
{
	float a = dot(rd, rd);
	float3 s0_r0 = r0 - s0;
	float b = 2.0 * dot(rd, s0_r0);
	float c = dot(s0_r0, s0_r0) - (sR * sR);
	float delta = b * b - 4.0*a*c;
	if (delta < 0.0 || a == 0.0)
	{
		return -1.0;
	}
	float sol0 = (-b - sqrt(delta)) / (2.0*a);
	float sol1 = (-b + sqrt(delta)) / (2.0*a);
	if (sol0 < 0.0 && sol1 < 0.0)
	{
		return -1.0;
	}
	if (sol0 < 0.0)
	{
		return max(0.0, sol1);
	}
	else if (sol1 < 0.0)
	{
		return max(0.0, sol0);
	}
	return max(0.0, min(sol0, sol1));
}

void LutTransmittanceParamsToUv(AtmosphereParameters atmosphere, in float view_height, in float view_zenith_cos_angle, out float2 uv)
{
	float H = sqrt(max(0.0f, atmosphere.top_radius * atmosphere.top_radius - atmosphere.bottom_radius * atmosphere.bottom_radius));
	float rho = sqrt(max(0.0f, view_height * view_height - atmosphere.bottom_radius * atmosphere.bottom_radius));

	float discriminant = view_height * view_height * (view_zenith_cos_angle * view_zenith_cos_angle - 1.0) + atmosphere.top_radius * atmosphere.top_radius;
	float d = max(0.0, (-view_height * view_zenith_cos_angle + sqrt(discriminant))); // Distance to atmosphere boundary

	float d_min = atmosphere.top_radius - view_height;
	float d_max = rho + H;
	float x_mu = (d - d_min) / (d_max - d_min);
	float x_r = rho / H;

	uv = float2(x_mu, x_r);
	//uv = float2(fromUnitToSubUvs(uv.x, TRANSMITTANCE_TEXTURE_WIDTH), fromUnitToSubUvs(uv.y, TRANSMITTANCE_TEXTURE_HEIGHT)); // No real impact so off
}