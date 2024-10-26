// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere

#include "render_sky_ray_marching_common.hlsli"

struct RayMarchPixelOutputStruct
{
	float4 luminance		: SV_TARGET0;
#if COLORED_TRANSMITTANCE_ENABLED
	float4 transmittance	: SV_TARGET1;
#endif
};

RayMarchPixelOutputStruct main(VertexOutput Input)
{
	RayMarchPixelOutputStruct output = (RayMarchPixelOutputStruct)0;
#if COLORED_TRANSMITTANCE_ENABLED
	output.transmittance = float4(0, 0, 0, 1);
#endif

	float2 pix_pos = Input.position.xy;
	AtmosphereParameters atmosphere = GetAtmosphereParameters();

	float3 clip_space = float3((pix_pos / float2(resolution))*float2(2.0, -2.0) - float2(1.0, -1.0), 0.0);
	float4 h_view_pos = mul(sky_inv_proj_mat, float4(clip_space, 1.0));
	float3 world_dir = normalize(mul((float3x3)sky_inv_view_mat, h_view_pos.xyz / h_view_pos.w));
	float3 world_pos = camera + float3(0, atmosphere.bottom_radius, 0);

	float depth_buffer_value = -1.0;

	//if (pix_pos.x < 512 && pix_pos.y < 512)
	//{
	//	output.luminance = float4(MultiScatTexture.SampleLevel(samplerLinearClamp, pix_pos / float2(512, 512), 0).rgb, 1.0);
	//	return output;
	//}

	float view_height = length(world_pos);
	float3 L = 0;
	depth_buffer_value = view_depth_texture[pix_pos].r;
#if FASTSKY_ENABLED
	// NOTE(gmodarelli): Tides uses a reversed z-buffer
	// if (view_height < atmosphere.top_radius && depth_buffer_value == 1.0f)
	if (view_height < atmosphere.top_radius && depth_buffer_value == 0.0f)
	{
		float2 uv;
		float3 up_vector = normalize(world_pos);
		float view_zenith_cos_angle = dot(world_dir, up_vector);

		float3 side_vector = normalize(cross(up_vector, world_dir));		// assumes non parallel vectors
		float3 forwardVector = normalize(cross(side_vector, up_vector));	// aligns toward the sun light but perpendicular to up vector
		float2 light_on_plane = float2(dot(sun_direction, forwardVector), dot(sun_direction, side_vector));
		light_on_plane = normalize(light_on_plane);
		float lightViewCosAngle = light_on_plane.x;

		bool intersect_ground = RaySphereIntersectNearest(world_pos, world_dir, float3(0, 0, 0), atmosphere.bottom_radius) >= 0.0f;

		SkyViewLutParamsToUv(atmosphere, intersect_ground, view_zenith_cos_angle, lightViewCosAngle, view_height, uv);


		//output.luminance = float4(SkyViewLutTexture.SampleLevel(samplerLinearClamp, pix_pos / float2(resolution), 0).rgb + GetSunLuminance(world_pos, world_dir, atmosphere.bottom_radius), 1.0);
		output.luminance = float4(sky_view_lut_texture.SampleLevel(sampler_linear_clamp, uv, 0).rgb + GetSunLuminance(world_pos, world_dir, atmosphere.bottom_radius), 1.0);
		return output;
	}
#else
	// NOTE(gmodarelli): Tides uses a reversed z-buffer
	// if (depth_buffer_value == 1.0f)
	if (depth_buffer_value == 0.0f)
		L += GetSunLuminance(world_pos, world_dir, atmosphere.bottom_radius);
#endif

#if FASTAERIALPERSPECTIVE_ENABLED

#if COLORED_TRANSMITTANCE_ENABLED
#error The FASTAERIALPERSPECTIVE_ENABLED path does not support COLORED_TRANSMITTANCE_ENABLED.
#else

	clip_space = float3((pix_pos / float2(resolution))*float2(2.0, -2.0) - float2(1.0, -1.0), depth_buffer_value);
	float4 depth_buffer_world_pos = mul(sky_inv_view_proj_mat, float4(clip_space, 1.0));
	depth_buffer_world_pos /= depth_buffer_world_pos.w;
	float t_depth = length(depth_buffer_world_pos.xyz - (world_pos + float3(0.0, -atmosphere.bottom_radius, 0.0)));
	float slice = AerialPerspectiveDepthToSlice(t_depth);
	float weight = 1.0;
	if (slice < 0.5)
	{
		// We multiply by weight to fade to 0 at depth 0. That works for luminance and opacity.
		weight = saturate(slice * 2.0);
		slice = 0.5;
	}
	float w = sqrt(slice / AP_SLICE_COUNT);	// squared distribution

	const float4 ap = weight * atmosphere_camera_scattering_volume.SampleLevel(sampler_linear_clamp, float3(pix_pos / float2(resolution), w), 0);
	L.rgb += ap.rgb;
	float opacity = ap.a;

	output.luminance = float4(L, opacity);
	//output.luminance *= frac(clamp(w*AP_SLICE_COUNT, 0, AP_SLICE_COUNT));
#endif

#else // FASTAERIALPERSPECTIVE_ENABLED

	// Move to top atmosphere as the starting point for ray marching.
	// This is critical to be after the above to not disrupt above atmosphere tests and voxel selection.
	if (!MoveToTopAtmosphere(world_pos, world_dir, atmosphere.top_radius))
	{
		// Ray is not intersecting the atmosphere
		output.luminance = float4(GetSunLuminance(world_pos, world_dir, atmosphere.bottom_radius), 1.0);
		return output;
	}

	const bool ground = false;
	const float sample_count_ini = 0.0f;
	const bool variable_sample_count = true;
	const bool mie_ray_phase = true;
	SingleScatteringResult ss = IntegrateScatteredLuminance(pix_pos, world_pos, world_dir, sun_direction, atmosphere, ground, sample_count_ini, depth_buffer_value, variable_sample_count, mie_ray_phase);

	L += ss.L;
	float3 throughput = ss.transmittance;

#if COLORED_TRANSMITTANCE_ENABLED
	output.luminance = float4(L, 1.0f);
	output.transmittance = float4(throughput, 1.0f);
#else
	const float transmittance = dot(throughput, float3(1.0f / 3.0f, 1.0f / 3.0f, 1.0f / 3.0f));
	output.luminance = float4(L, 1.0 - transmittance);
#endif

#endif // FASTAERIALPERSPECTIVE_ENABLED

	return output;
}
