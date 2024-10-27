// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere
#pragma once

#include "render_sky_common.hlsli"

struct SingleScatteringResult
{
	float3 L;						// Scattered light (luminance)
	float3 optical_depth;			// Optical depth (1/m)
	float3 transmittance;			// Transmittance in [0,1] (unitless)
	float3 multi_scat_as_1;

	float3 new_multi_scat_step_0_out;
	float3 new_multi_scat_step_1_out;
};

SingleScatteringResult IntegrateScatteredLuminance(
	in float2 pix_pos, in float3 world_pos, in float3 world_dir, in float3 sun_dir, in AtmosphereParameters atmosphere,
	in bool ground, in float sample_count_ini, in float depth_buffer_value, in bool variable_sample_count,
	in bool mie_ray_phase, in float t_max_max = 9000000.0f)
{
	SingleScatteringResult result = (SingleScatteringResult)0;

	float3 clip_space = float3((pix_pos / float2(resolution))*float2(2.0, -2.0) - float2(1.0, -1.0), 1.0);

	// Compute next intersection with atmosphere or ground
	float3 earth_o = float3(0.0f, 0.0f, 0.0f);
	float t_bottom = RaySphereIntersectNearest(world_pos, world_dir, earth_o, atmosphere.bottom_radius);
	float t_top = RaySphereIntersectNearest(world_pos, world_dir, earth_o, atmosphere.top_radius);
	float t_max = 0.0f;
	if (t_bottom < 0.0f)
	{
		if (t_top < 0.0f)
		{
			t_max = 0.0f; // No intersection with earth nor atmosphere: stop right away
			return result;
		}
		else
		{
			t_max = t_top;
		}
	}
	else
	{
		if (t_top > 0.0f)
		{
			t_max = min(t_top, t_bottom);
		}
	}

	if (depth_buffer_value >= 0.0f)
	{
		clip_space.z = depth_buffer_value;
		if (clip_space.z < 1.0f)
		{
			float4 depth_buffer_world_pos = mul(sky_inv_view_proj_mat, float4(clip_space, 1.0));
			depth_buffer_world_pos /= depth_buffer_world_pos.w;

			float t_depth = length(depth_buffer_world_pos.xyz - (world_pos + float3(0.0, -atmosphere.bottom_radius, 0.0))); // apply earth offset to go back to origin as top of earth mode.
			if (t_depth < t_max)
			{
				t_max = t_depth;
			}
		}
		//		if (variable_sample_count && clip_space.z == 1.0f)
		//			return result;
	}
	t_max = min(t_max, t_max_max);

	// Sample count
	float sample_count = sample_count_ini;
	float sample_count_floor = sample_count_ini;
	float t_max_floor = t_max;
	if (variable_sample_count)
	{
		sample_count = lerp(ray_march_min_max_spp.x, ray_march_min_max_spp.y, saturate(t_max*0.01));
		sample_count_floor = floor(sample_count);
		t_max_floor = t_max * sample_count_floor / sample_count;	// rescale t_max to map to the last entire step segment.
	}
	float dt = t_max / sample_count;

	// Phase functions
	const float uniform_phase = 1.0 / (4.0 * PI);
	const float3 wi = sun_dir;
	const float3 wo = world_dir;
	float cos_theta = dot(wi, wo);
	float mie_phase_value = HgPhase(atmosphere.mie_phase_g, -cos_theta);	// mnegate cos_theta because due to world_dir being a "in" direction.
	float rayleigh_phase_value = RayleighPhase(cos_theta);

#ifdef ILLUMINANCE_IS_ONE
	// When building the scattering factor, we assume light illuminance is 1 to compute a transfert function relative to identity illuminance of 1.
	// This make the scattering factor independent of the light. It is now only linked to the atmosphere properties.
	float3 global_l = 1.0f;
#else
	float3 global_l = sun_illuminance;
#endif

	// Ray march the atmosphere to integrate optical depth
	float3 L = 0.0f;
	float3 throughput = 1.0;
	float3 optical_depth = 0.0;
	float t = 0.0f;
	float t_prev = 0.0;
	const float sample_segment_t = 0.3f;
	for (float s = 0.0f; s < sample_count; s += 1.0f)
	{
		if (variable_sample_count)
		{
			// More expenssive but artefact free
			float t0 = (s) / sample_count_floor;
			float t1 = (s + 1.0f) / sample_count_floor;
			// Non linear distribution of sample within the range.
			t0 = t0 * t0;
			t1 = t1 * t1;
			// Make t0 and t1 world space distances.
			t0 = t_max_floor * t0;
			if (t1 > 1.0)
			{
				t1 = t_max;
				//	t1 = t_max_floor;	// this reveal depth slices
			}
			else
			{
				t1 = t_max_floor * t1;
			}
			t = t0 + (t1 - t0)*sample_segment_t;
			dt = t1 - t0;
		}
		else
		{
			//t = t_max * (s + sample_segment_t) / sample_count;
			// Exact difference, important for accuracy of multiple scattering
			float new_t = t_max * (s + sample_segment_t) / sample_count;
			dt = new_t - t;
			t = new_t;
		}
		float3 P = world_pos + t * world_dir;

		MediumSampleRGB medium = SampleMediumRGB(P, atmosphere);
		const float3 sample_optical_depth = medium.extinction * dt;
		const float3 sample_transmittance = exp(-sample_optical_depth);
		optical_depth += sample_optical_depth;

		float p_height = length(P);
		const float3 up_vector = P / p_height;
		float sun_zenith_cos_angle = dot(sun_dir, up_vector);
		float2 uv;
		LutTransmittanceParamsToUv(atmosphere, p_height, sun_zenith_cos_angle, uv);
		float3 transmittance_to_sun = transmittance_lut_texture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;

		float3 phase_times_scattering;
		if (mie_ray_phase)
		{
			phase_times_scattering = medium.scattering_mie * mie_phase_value + medium.scattering_ray * rayleigh_phase_value;
		}
		else
		{
			phase_times_scattering = medium.scattering * uniform_phase;
		}

		// Earth shadow
		float t_earth = RaySphereIntersectNearest(P, sun_dir, earth_o + PLANET_RADIUS_OFFSET * up_vector, atmosphere.bottom_radius);
		float earthShadow = t_earth >= 0.0f ? 0.0f : 1.0f;

		// Dual scattering for multi scattering

		float3 multi_scattered_luminance = 0.0f;
#if MULTISCATAPPROX_ENABLED
		multi_scattered_luminance = GetMultipleScattering(atmosphere, medium.scattering, medium.extinction, P, sun_zenith_cos_angle);
#endif

		float shadow = 1.0f;
#if SHADOWMAP_ENABLED
        // TODO(gmodarelli): Enable Shadow Map
		// First evaluate opaque shadow
		// shadow = GetShadow(Atmosphere, P);
#endif

		float3 S = global_l * (earthShadow * shadow * transmittance_to_sun * phase_times_scattering + multi_scattered_luminance * medium.scattering);

		// When using the power serie to accumulate all sattering order, serie r must be <1 for a serie to converge.
		// Under extreme coefficient, multi_scat_as_1 can grow larger and thus result in broken visuals.
		// The way to fix that is to use a proper analytical integration as proposed in slide 28 of http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
		// However, it is possible to disable as it can also work using simple power serie sum unroll up to 5th order. The rest of the orders has a really low contribution.
#define MULTI_SCATTERING_POWER_SERIE 1

#if MULTI_SCATTERING_POWER_SERIE==0
		// 1 is the integration of luminance over the 4pi of a sphere, and assuming an isotropic phase function of 1.0/(4*PI)
		result.multi_scat_as_1 += throughput * medium.scattering * 1 * dt;
#else
		float3 MS = medium.scattering * 1;
		float3 MSint = (MS - MS * sample_transmittance) / medium.extinction;
		result.multi_scat_as_1 += throughput * MSint;
#endif

		// Evaluate input to multi scattering
		{
			float3 newMS;

			newMS = earthShadow * transmittance_to_sun * medium.scattering * uniform_phase * 1;
			result.new_multi_scat_step_0_out += throughput * (newMS - newMS * sample_transmittance) / medium.extinction;
			//	result.new_multi_scat_step_0_out += sample_transmittance * throughput * newMS * dt;

			newMS = medium.scattering * uniform_phase * multi_scattered_luminance;
			result.new_multi_scat_step_1_out += throughput * (newMS - newMS * sample_transmittance) / medium.extinction;
			//	result.new_multi_scat_step_1_out += sample_transmittance * throughput * newMS * dt;
		}

#if 0
		L += throughput * S * dt;
		throughput *= sample_transmittance;
#else
		// See slide 28 at http://www.frostbite.com/2015/08/physically-based-unified-volumetric-rendering-in-frostbite/
		float3 Sint = (S - S * sample_transmittance) / medium.extinction;	// integrate along the current step segment
		L += throughput * Sint;														// accumulate and also take into account the transmittance from previous steps
		throughput *= sample_transmittance;
#endif

		t_prev = t;
	}

	if (ground && t_max == t_bottom && t_bottom > 0.0)
	{
		// Account for bounced light off the earth
		float3 P = world_pos + t_bottom * world_dir;
		float p_height = length(P);

		const float3 up_vector = P / p_height;
		float sun_zenith_cos_angle = dot(sun_dir, up_vector);
		float2 uv;
		LutTransmittanceParamsToUv(atmosphere, p_height, sun_zenith_cos_angle, uv);
		float3 transmittance_to_sun = transmittance_lut_texture.SampleLevel(sampler_linear_clamp, uv, 0).rgb;

		const float n_dot_l = saturate(dot(normalize(up_vector), normalize(sun_dir)));
		L += global_l * transmittance_to_sun * throughput * n_dot_l * atmosphere.ground_albedo / PI;
	}

	result.L = L;
	result.optical_depth = optical_depth;
	result.transmittance = throughput;
	return result;
}

#define AP_SLICE_COUNT 32.0f
#define AP_KM_PER_SLICE 4.0f

float AerialPerspectiveDepthToSlice(float depth)
{
	return depth * (1.0f / AP_KM_PER_SLICE);
}
float AerialPerspectiveSliceToDepth(float slice)
{
	return slice * AP_KM_PER_SLICE;
}
