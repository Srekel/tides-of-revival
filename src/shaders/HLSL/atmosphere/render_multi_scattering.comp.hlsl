// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere

#include "render_sky_ray_marching_common.hlsli"

groupshared float3 multi_scat_as_1_shared_mem[64];
groupshared float3 l_shared_mem[64];

[numthreads(1, 1, 64)]
void main(uint3 thread_id : SV_DispatchThreadID)
{
	float2 pix_pos = float2(thread_id.xy) + 0.5f;
	float2 uv = pix_pos / multi_scattering_LUT_res;

	uv = float2(FromSubUvsToUnit(uv.x, multi_scattering_LUT_res), FromSubUvsToUnit(uv.y, multi_scattering_LUT_res));

	AtmosphereParameters atmosphere = GetAtmosphereParameters();

	float cos_sun_zenith_angle = uv.x * 2.0 - 1.0;
	float3 sun_dir = float3(0.0, sqrt(saturate(1.0 - cos_sun_zenith_angle * cos_sun_zenith_angle)), cos_sun_zenith_angle);
	// We adjust again viewHeight according to PLANET_RADIUS_OFFSET to be in a valid range.
	float view_height = atmosphere.bottom_radius + saturate(uv.y + PLANET_RADIUS_OFFSET) * (atmosphere.top_radius - atmosphere.bottom_radius - PLANET_RADIUS_OFFSET);

	float3 world_pos = float3(0.0f, 0.0f, view_height);
	float3 world_dir = float3(0.0f, 0.0f, 1.0f);

	const bool ground = true;
	const float sample_count_ini = 20;// a minimum set of step is required for accuracy unfortunately
	const float depth_buffer_value = -1.0;
	const bool variable_sample_count = false;
	const bool mie_ray_phase = false;

	const float sphere_solid_angle = 4.0 * PI;
	const float isotropic_phase = 1.0 / sphere_solid_angle;


	// Reference. Since there are many sample, it requires MULTI_SCATTERING_POWER_SERIE to be true for accuracy and to avoid divergences (see declaration for explanations)
#define SQRTSAMPLECOUNT 8
	const float sqrt_sample = float(SQRTSAMPLECOUNT);
	float i = 0.5f + float(thread_id.z / SQRTSAMPLECOUNT);
	float j = 0.5f + float(thread_id.z - float((thread_id.z / SQRTSAMPLECOUNT)*SQRTSAMPLECOUNT));
	{
		float rand_a = i / sqrt_sample;
		float rand_b = j / sqrt_sample;
		float theta = 2.0f * PI * rand_a;
		float phi = acos(1.0f - 2.0f * rand_b);	// uniform distribution https://mathworld.wolfram.com/SpherePointPicking.html
		//phi = PI * rand_b;						// bad non uniform
		float cos_phi = cos(phi);
		float sin_phi = sin(phi);
		float cos_theta = cos(theta);
		float sin_theta = sin(theta);
		world_dir.x = cos_theta * sin_phi;
		world_dir.y = sin_theta * sin_phi;
		world_dir.z = cos_phi;
		SingleScatteringResult result = IntegrateScatteredLuminance(pix_pos, world_pos, world_dir, sun_dir, atmosphere, ground, sample_count_ini, depth_buffer_value, variable_sample_count, mie_ray_phase);

		multi_scat_as_1_shared_mem[thread_id.z] = result.multi_scat_as_1 * sphere_solid_angle / (sqrt_sample * sqrt_sample);
		l_shared_mem[thread_id.z] = result.L * sphere_solid_angle / (sqrt_sample * sqrt_sample);
	}
#undef SQRTSAMPLECOUNT

	GroupMemoryBarrierWithGroupSync();

	// 64 to 32
	if (thread_id.z < 32)
	{
		multi_scat_as_1_shared_mem[thread_id.z] += multi_scat_as_1_shared_mem[thread_id.z + 32];
		l_shared_mem[thread_id.z] += l_shared_mem[thread_id.z + 32];
	}
	GroupMemoryBarrierWithGroupSync();

	// 32 to 16
	if (thread_id.z < 16)
	{
		multi_scat_as_1_shared_mem[thread_id.z] += multi_scat_as_1_shared_mem[thread_id.z + 16];
		l_shared_mem[thread_id.z] += l_shared_mem[thread_id.z + 16];
	}
	GroupMemoryBarrierWithGroupSync();

	// 16 to 8 (16 is thread group min hardware size with intel, no sync required from there)
	if (thread_id.z < 8)
	{
		multi_scat_as_1_shared_mem[thread_id.z] += multi_scat_as_1_shared_mem[thread_id.z + 8];
		l_shared_mem[thread_id.z] += l_shared_mem[thread_id.z + 8];
	}
	GroupMemoryBarrierWithGroupSync();
	if (thread_id.z < 4)
	{
		multi_scat_as_1_shared_mem[thread_id.z] += multi_scat_as_1_shared_mem[thread_id.z + 4];
		l_shared_mem[thread_id.z] += l_shared_mem[thread_id.z + 4];
	}
	GroupMemoryBarrierWithGroupSync();
	if (thread_id.z < 2)
	{
		multi_scat_as_1_shared_mem[thread_id.z] += multi_scat_as_1_shared_mem[thread_id.z + 2];
		l_shared_mem[thread_id.z] += l_shared_mem[thread_id.z + 2];
	}
	GroupMemoryBarrierWithGroupSync();
	if (thread_id.z < 1)
	{
		multi_scat_as_1_shared_mem[thread_id.z] += multi_scat_as_1_shared_mem[thread_id.z + 1];
		l_shared_mem[thread_id.z] += l_shared_mem[thread_id.z + 1];
	}
	GroupMemoryBarrierWithGroupSync();
	if (thread_id.z > 0)
		return;

	float3 multi_scat_as_1			= multi_scat_as_1_shared_mem[0] * isotropic_phase;	// Equation 7 f_ms
	float3 in_scattered_luminance	= l_shared_mem[0] * isotropic_phase;				// Equation 5 L_2ndOrder

	// multi_scat_as_1 represents the amount of luminance scattered as if the integral of scattered luminance over the sphere would be 1.
	//  - 1st order of scattering: one can ray-march a straight path as usual over the sphere. That is in_scattered_luminance.
	//  - 2nd order of scattering: the inscattered luminance is in_scattered_luminance at each of samples of fist order integration. Assuming a uniform phase function that is represented by multi_scat_as_1,
	//  - 3nd order of scattering: the inscattered luminance is (in_scattered_luminance * multi_scat_as_1 * multi_scat_as_1)
	//  - etc.
#if	MULTI_SCATTERING_POWER_SERIE==0
	float3 multi_scat_as_1_sqr = multi_scat_as_1 * multi_scat_as_1;
	float3 L = in_scattered_luminance * (1.0 + multi_scat_as_1 + multi_scat_as_1_sqr + multi_scat_as_1 * multi_scat_as_1_sqr + multi_scat_as_1_sqr * multi_scat_as_1_sqr);
#else
	// For a serie, sum_{n=0}^{n=+inf} = 1 + r + r^2 + r^3 + ... + r^n = 1 / (1.0 - r), see https://en.wikipedia.org/wiki/Geometric_series
	const float3 r = multi_scat_as_1;
	const float3 sum_of_all_multi_scattering_events_contribution = 1.0f / (1.0 - r);
	float3 L = in_scattered_luminance * sum_of_all_multi_scattering_events_contribution;// Equation 10 Psi_ms
#endif

	output_texture[thread_id.xy] = float4(multiple_scattering_factor * L, 1.0f);
}
