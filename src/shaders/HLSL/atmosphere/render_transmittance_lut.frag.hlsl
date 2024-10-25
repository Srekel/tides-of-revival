// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere

#include "render_sky_ray_marching_common.hlsli"

float4 main(VertexOutput Input) : SV_TARGET
{
	float2 pix_pos = Input.position.xy;
	AtmosphereParameters atmosphere = GetAtmosphereParameters();

	// Compute camera position from LUT coords
	float2 uv = (pix_pos) / float2(transmittance_texture_width, transmittance_texture_height);
	float view_height;
	float view_zenith_cos_angle;
	UvToLutTransmittanceParams(atmosphere, view_height, view_zenith_cos_angle, uv);

	//  A few extra needed constants
	float3 world_pos = float3(0.0f, 0.0f, view_height);
	float3 world_dir = float3(0.0f, sqrt(1.0 - view_zenith_cos_angle * view_zenith_cos_angle), view_zenith_cos_angle);

	const bool ground = false;
	const float sample_count_ini = 40.0f;	// Can go a low as 10 sample but energy lost starts to be visible.
	const float depth_buffer_value = -1.0;
	const bool variable_sample_count = false;
	const bool mie_ray_phase = false;
	float3 transmittance = exp(-IntegrateScatteredLuminance(pix_pos, world_pos, world_dir, sun_direction, atmosphere, ground, sample_count_ini, depth_buffer_value, variable_sample_count, mie_ray_phase).optical_depth);

	// Optical depth to transmittance
	return float4(transmittance, 1.0f);
}
