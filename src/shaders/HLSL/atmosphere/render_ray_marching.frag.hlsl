// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere

#include "render_sky_ray_marching_common.hlsli"

float4 main(VertexOutput Input) : SV_TARGET0
{
	float4 luminance = 0;

	float2 pix_pos = Input.position.xy;
	AtmosphereParameters atmosphere = GetAtmosphereParameters();

	float3 clip_space = float3((pix_pos / float2(resolution))*float2(2.0, -2.0) - float2(1.0, -1.0), 1.0);
	float4 h_view_pos = mul(sky_inv_proj_mat, float4(clip_space, 1.0));
	float3 world_dir = normalize(mul((float3x3)sky_inv_view_mat, h_view_pos.xyz / h_view_pos.w));
	float3 world_pos = camera + float3(0, atmosphere.bottom_radius, 0);

	float depth_buffer_value = -1.0;

	float view_height = length(world_pos);
	float3 L = 0;
	depth_buffer_value = view_depth_texture[pix_pos].r;
	// NOTE(gmodarelli): Tides uses a reversed z-buffer
	// if (depth_buffer_value == 1.0f)
	if (depth_buffer_value == 0.0f)
		L += GetSunLuminance(world_pos, world_dir, atmosphere.bottom_radius);

	// Move to top atmosphere as the starting point for ray marching.
	// This is critical to be after the above to not disrupt above atmosphere tests and voxel selection.
	if (!MoveToTopAtmosphere(world_pos, world_dir, atmosphere.top_radius))
	{
		// Ray is not intersecting the atmosphere
		luminance = float4(GetSunLuminance(world_pos, world_dir, atmosphere.bottom_radius), 1.0);
		return luminance;
	}

	const bool ground = false;
	const float sample_count_ini = 0.0f;
	const bool variable_sample_count = true;
	const bool mie_ray_phase = true;
	SingleScatteringResult ss = IntegrateScatteredLuminance(pix_pos, world_pos, world_dir, sun_direction, atmosphere, ground, sample_count_ini, depth_buffer_value, variable_sample_count, mie_ray_phase);

	L += ss.L;
	float3 throughput = ss.transmittance;
	const float transmittance = dot(throughput, float3(1.0f / 3.0f, 1.0f / 3.0f, 1.0f / 3.0f));
	luminance = float4(L, 1.0 - transmittance);

	return luminance;
}
