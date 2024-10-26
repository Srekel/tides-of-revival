// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere

// TODO(gmodarelli): This macro should be specified a compile time,
// but we don't have support for it with the current shader compilation pipeline
#define MULTISCATAPPROX_ENABLED 1

#include "render_sky_ray_marching_common.hlsli"

float4 main(GeometryOutput Input) : SV_TARGET0
{
	float2 pix_pos = Input.position.xy;
	AtmosphereParameters atmosphere = GetAtmosphereParameters();

	float3 clip_space = float3((pix_pos / float2(resolution))*float2(2.0, -2.0) - float2(1.0, -1.0), 0.5);
	float4 h_view_pos = mul(sky_inv_proj_mat, float4(clip_space, 1.0));
	float3 world_dir = normalize(mul((float3x3)sky_inv_view_mat, h_view_pos.xyz / h_view_pos.w));

	float earth_r = atmosphere.bottom_radius;
	float3 earth_o = float3(0.0, -earth_r, 0.0);
	float3 cam_pos = camera + float3(0, earth_r, 0.0);
	float3 sun_dir = sun_direction;
	float3 sun_luminance = 0.0;

	float slice = ((float(Input.slice_id) + 0.5f) / AP_SLICE_COUNT);
	slice *= slice;	// squared distribution
	slice *= AP_SLICE_COUNT;

	float3 world_pos = cam_pos;
	float view_height;

	// Compute position from froxel information
	float t_max = AerialPerspectiveSliceToDepth(slice);
	float3 new_world_pos = world_pos + t_max * world_dir;

	// If the voxel is under the ground, make sure to offset it out on the ground.
	view_height = length(new_world_pos);
	if (view_height <= (atmosphere.bottom_radius + PLANET_RADIUS_OFFSET))
	{
		// Apply a position offset to make sure no artefact are visible close to the earth boundaries for large voxel.
		new_world_pos = normalize(new_world_pos) * (atmosphere.bottom_radius + PLANET_RADIUS_OFFSET + 0.001f);
		world_dir = normalize(new_world_pos - cam_pos);
		t_max = length(new_world_pos - cam_pos);
	}
	float t_max_max = t_max;

	// Move ray marching start up to top atmosphere.
	view_height = length(world_pos);
	if (view_height >= atmosphere.top_radius)
	{
		float3 prev_world_pos = world_pos;
		if (!MoveToTopAtmosphere(world_pos, world_dir, atmosphere.top_radius))
		{
			// Ray is not intersecting the atmosphere
			return float4(0.0, 0.0, 0.0, 1.0);
		}
		float length_to_atmosphere = length(prev_world_pos - world_pos);
		if (t_max_max < length_to_atmosphere)
		{
			// t_max_max for this voxel is not within earth atmosphere
			return float4(0.0, 0.0, 0.0, 1.0);
		}
		// Now world position has been moved to the atmosphere boundary: we need to reduce t_max_max accordingly.
		t_max_max = max(0.0, t_max_max - length_to_atmosphere);
	}

	const bool ground = false;
	const float sample_count_ini = max(1.0, float(Input.slice_id + 1.0) * 2.0f);
	const float depth_buffer_value = -1.0;
	const bool variable_sample_count = false;
	const bool mie_ray_phase = true;

	SingleScatteringResult ss = IntegrateScatteredLuminance(pix_pos, world_pos, world_dir, sun_dir, atmosphere, ground, sample_count_ini, depth_buffer_value, variable_sample_count, mie_ray_phase, t_max_max);
	const float transmittance = dot(ss.transmittance, float3(1.0f / 3.0f, 1.0f / 3.0f, 1.0f / 3.0f));
	return float4(ss.L, 1.0 - transmittance);
}
