// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere
#pragma once

#include "sky_atmosphere_common.hlsli"

Texture2D<float4> transmittance_lut_texture : register(t2, UPDATE_FREQ_PER_FRAME);
Texture2D<float4> sky_view_lut_texture : register(t3, UPDATE_FREQ_PER_FRAME);

Texture2D<float4> view_depth_texture : register(t4, UPDATE_FREQ_PER_FRAME);
Texture2D<float4> shadowmap_texture : register(t5, UPDATE_FREQ_PER_FRAME);

Texture2D<float4> multi_scat_texture : register(t6, UPDATE_FREQ_PER_FRAME);
Texture3D<float4> atmosphere_camera_scattering_volume : register(t7, UPDATE_FREQ_PER_FRAME);

RWTexture2D<float4> output_texture : register(u0, UPDATE_FREQ_PER_FRAME);
RWTexture2D<float4> output_texture1 : register(u1, UPDATE_FREQ_PER_FRAME);


#define RAYDPOS 0.00001f

#ifndef SHADOWMAP_ENABLED
#define SHADOWMAP_ENABLED 0
#endif

#define RENDER_SUN_DISK 1

#if 1
#define USE_CornetteShanks
#define MIE_PHASE_IMPORTANCE_SAMPLING 0
#else
// Beware: untested, probably faulty code path.
// Mie importance sampling is only used for multiple scattering. Single scattering is fine and noise only due to sample selection on view ray.
// A bit more expenssive so off for now.
#define MIE_PHASE_IMPORTANCE_SAMPLING 1
#endif


#define PLANET_RADIUS_OFFSET 0.01f

struct Ray
{
	float3 o;
	float3 d;
};

Ray CreateRay(in float3 p, in float3 d)
{
	Ray r;
	r.o = p;
	r.d = d;
	return r;
}

////////////////////////////////////////////////////////////
// LUT functions
////////////////////////////////////////////////////////////

// Transmittance LUT function parameterisation from Bruneton 2017 https://github.com/ebruneton/precomputed_atmospheric_scattering
// uv in [0,1]
// view_zenith_cos_angle in [-1,1]
// view_height in [bottom_radius, top_radius]

// We should precompute those terms from resolutions (Or set resolution as #defined constants)
float FromUnitToSubUvs(float u, float resolution) { return (u + 0.5f / resolution) * (resolution / (resolution + 1.0f)); }
float FromSubUvsToUnit(float u, float resolution) { return (u - 0.5f / resolution) * (resolution / (resolution - 1.0f)); }

void UvToLutTransmittanceParams(AtmosphereParameters atmosphere, out float view_height, out float view_zenith_cos_angle, in float2 uv)
{
	//uv = float2(FromSubUvsToUnit(uv.x, TRANSMITTANCE_TEXTURE_WIDTH), FromSubUvsToUnit(uv.y, TRANSMITTANCE_TEXTURE_HEIGHT)); // No real impact so off
	float x_mu = uv.x;
	float x_r = uv.y;

	float H = sqrt(atmosphere.top_radius * atmosphere.top_radius - atmosphere.bottom_radius * atmosphere.bottom_radius);
	float rho = H * x_r;
	view_height = sqrt(rho * rho + atmosphere.bottom_radius * atmosphere.bottom_radius);

	float d_min = atmosphere.top_radius - view_height;
	float d_max = rho + H;
	float d = d_min + x_mu * (d_max - d_min);
	view_zenith_cos_angle = d == 0.0 ? 1.0f : (H * H - rho * rho - d * d) / (2.0 * view_height * d);
	view_zenith_cos_angle = clamp(view_zenith_cos_angle, -1.0, 1.0);
}

#define NONLINEARSKYVIEWLUT 1
void UvToSkyViewLutParams(AtmosphereParameters atmosphere, out float view_zenith_cos_angle, out float light_view_cos_angle, in float view_height, in float2 uv)
{
	// Constrain uvs to valid sub texel range (avoid zenith derivative issue making LUT usage visible)
	uv = float2(FromSubUvsToUnit(uv.x, 192.0f), FromSubUvsToUnit(uv.y, 108.0f));

	float v_horizon = sqrt(view_height * view_height - atmosphere.bottom_radius * atmosphere.bottom_radius);
	float cos_beta = v_horizon / view_height;				// GroundToHorizonCos
	float beta = acos(cos_beta);
	float zenith_horizon_angle = PI - beta;

	if (uv.y < 0.5f)
	{
		float coord = 2.0*uv.y;
		coord = 1.0 - coord;
#if NONLINEARSKYVIEWLUT
		coord *= coord;
#endif
		coord = 1.0 - coord;
		view_zenith_cos_angle = cos(zenith_horizon_angle * coord);
	}
	else
	{
		float coord = uv.y*2.0 - 1.0;
#if NONLINEARSKYVIEWLUT
		coord *= coord;
#endif
		view_zenith_cos_angle = cos(zenith_horizon_angle + beta * coord);
	}

	float coord = uv.x;
	coord *= coord;
	light_view_cos_angle = -(coord*2.0 - 1.0);
}

void SkyViewLutParamsToUv(AtmosphereParameters atmosphere, in bool intersect_ground, in float view_zenith_cos_angle, in float light_view_cos_angle, in float view_height, out float2 uv)
{
	float v_horizon = sqrt(view_height * view_height - atmosphere.bottom_radius * atmosphere.bottom_radius);
	float cos_beta = v_horizon / view_height;				// GroundToHorizonCos
	float beta = acos(cos_beta);
	float zenith_horizon_angle = PI - beta;

	if (!intersect_ground)
	{
		float coord = acos(view_zenith_cos_angle) / zenith_horizon_angle;
		coord = 1.0 - coord;
#if NONLINEARSKYVIEWLUT
		coord = sqrt(coord);
#endif
		coord = 1.0 - coord;
		uv.y = coord * 0.5f;
	}
	else
	{
		float coord = (acos(view_zenith_cos_angle) - zenith_horizon_angle) / beta;
#if NONLINEARSKYVIEWLUT
		coord = sqrt(coord);
#endif
		uv.y = coord * 0.5f + 0.5f;
	}

	{
		float coord = -light_view_cos_angle * 0.5f + 0.5f;
		coord = sqrt(coord);
		uv.x = coord;
	}

	// Constrain uvs to valid sub texel range (avoid zenith derivative issue making LUT usage visible)
	uv = float2(FromUnitToSubUvs(uv.x, 192.0f), FromUnitToSubUvs(uv.y, 108.0f));
}

////////////////////////////////////////////////////////////
// Participating media
////////////////////////////////////////////////////////////

float GetAlbedo(float scattering, float extinction)
{
	return scattering / max(0.001, extinction);
}
float3 GetAlbedo(float3 scattering, float3 extinction)
{
	return scattering / max(0.001, extinction);
}

struct MediumSampleRGB
{
	float3 scattering;
	float3 absorption;
	float3 extinction;

	float3 scattering_mie;
	float3 absorption_mie;
	float3 extinction_mie;

	float3 scattering_ray;
	float3 absorption_ray;
	float3 extinction_ray;

	float3 scattering_ozo;
	float3 absorption_ozo;
	float3 extinction_ozo;

	float3 albedo;
};

MediumSampleRGB SampleMediumRGB(in float3 world_pos, in AtmosphereParameters atmosphere)
{
	const float view_height = length(world_pos) - atmosphere.bottom_radius;

	const float density_mie = exp(atmosphere.mie_density_exp_scale * view_height);
	const float density_ray = exp(atmosphere.rayleigh_density_exp_scale * view_height);
	const float density_ozo = saturate(view_height < atmosphere.absorption_density_0_layer_width ?
		atmosphere.absorption_density_0_linear_term * view_height + atmosphere.absorption_density_0_constant_term :
		atmosphere.absorption_density_1_linear_term * view_height + atmosphere.absorption_density_1_constant_term);

	MediumSampleRGB s;

	s.scattering_mie = density_mie * atmosphere.mie_scattering;
	s.absorption_mie = density_mie * atmosphere.mie_absorption;
	s.extinction_mie = density_mie * atmosphere.mie_extinction;

	s.scattering_ray = density_ray * atmosphere.rayleigh_scattering;
	s.absorption_ray = 0.0f;
	s.extinction_ray = s.scattering_ray + s.absorption_ray;

	s.scattering_ozo = 0.0;
	s.absorption_ozo = density_ozo * atmosphere.absorption_extinction;
	s.extinction_ozo = s.scattering_ozo + s.absorption_ozo;

	s.scattering = s.scattering_mie + s.scattering_ray + s.scattering_ozo;
	s.absorption = s.absorption_mie + s.absorption_ray + s.absorption_ozo;
	s.extinction = s.extinction_mie + s.extinction_ray + s.extinction_ozo;
	s.albedo = GetAlbedo(s.scattering, s.extinction);

	return s;
}

////////////////////////////////////////////////////////////
// Sampling functions
////////////////////////////////////////////////////////////

float RayleighPhase(float cos_theta)
{
	float factor = 3.0f / (16.0f * PI);
	return factor * (1.0f + cos_theta * cos_theta);
}

float CornetteShanksMiePhaseFunction(float g, float cos_theta)
{
	float k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
	return k * (1.0 + cos_theta * cos_theta) / pow(1.0 + g * g - 2.0 * g * -cos_theta, 1.5);
}

float HgPhase(float g, float cos_theta)
{
#ifdef USE_CornetteShanks
	return CornetteShanksMiePhaseFunction(g, cos_theta);
#else
	// Reference implementation (i.e. not schlick approximation).
	// See http://www.pbr-book.org/3ed-2018/Volume_Scattering/Phase_Functions.html
	float numer = 1.0f - g * g;
	float denom = 1.0f + g * g + 2.0f * g * cos_theta;
	return numer / (4.0f * PI * denom * sqrt(denom));
#endif
}

////////////////////////////////////////////////////////////
// Misc functions
////////////////////////////////////////////////////////////

bool MoveToTopAtmosphere(inout float3 world_pos, in float3 world_dir, in float atmosphere_top_radius)
{
	float view_height = length(world_pos);
	if (view_height > atmosphere_top_radius)
	{
		float t_top = RaySphereIntersectNearest(world_pos, world_dir, float3(0.0f, 0.0f, 0.0f), atmosphere_top_radius);
		if (t_top >= 0.0f)
		{
			float3 up_vector = world_pos / view_height;
			float3 up_offset = up_vector * -PLANET_RADIUS_OFFSET;
			world_pos = world_pos + world_dir * t_top + up_offset;
		}
		else
		{
			// Ray is not intersecting the atmosphere
			return false;
		}
	}
	return true; // ok to start tracing
}

float3 GetSunLuminance(float3 world_pos, float3 world_dir, float planet_radius)
{
#if RENDER_SUN_DISK
	const float sun_angle = cos(sun_angular_radius);
	const float3 sun_luminance = 1000.0; // arbitrary. But fine, not use when comparing the models
	if (dot(world_dir, sun_direction) > sun_angle)
	{
		float t = RaySphereIntersectNearest(world_pos, world_dir, float3(0.0f, 0.0f, 0.0f), planet_radius);
		if (t < 0.0f) // no intersection
		{
            return sun_luminance;
		}
	}
#endif
	return 0;
}

float3 GetMultipleScattering(AtmosphereParameters atmosphere, float3 scattering, float3 extinction, float3 worlPos, float view_zenith_cos_angle)
{
	float2 uv = saturate(float2(view_zenith_cos_angle*0.5f + 0.5f, (length(worlPos) - atmosphere.bottom_radius) / (atmosphere.top_radius - atmosphere.bottom_radius)));
	uv = float2(FromUnitToSubUvs(uv.x, multi_scattering_LUT_res), FromUnitToSubUvs(uv.y, multi_scattering_LUT_res));

	float3 multi_scattered_luminance = multi_scat_texture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;
	return multi_scattered_luminance;
}

// TODO(gmodarelli): Enable Shadow Map
/*
float GetShadow(in AtmosphereParameters atmosphere, float3 P)
{
	// First evaluate opaque shadow
	float4 shadow_uv = mul(shadowmap_view_proj_mat, float4(P + float3(0.0, 0.0, -atmosphere.bottom_radius), 1.0));
	//shadow_uv /= shadow_uv.w;	// not be needed as it is an ortho projection
	shadow_uv.x = shadow_uv.x*0.5 + 0.5;
	shadow_uv.y = -shadow_uv.y*0.5 + 0.5;
	if (all(shadow_uv.xyz >= 0.0) && all(shadow_uv.xyz < 1.0))
	{
		return shadowmap_texture.SampleCmpLevelZero(sampler_shadow, shadow_uv.xy, shadow_uv.z);
	}
	return 1.0f;
}
*/