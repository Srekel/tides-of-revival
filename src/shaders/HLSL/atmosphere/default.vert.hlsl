// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere
#include "sky_atmosphere_common.hlsli"

VertexOutput main(VertexInput input)
{
	VertexOutput output = (VertexOutput)0;

	// Calculate the position of the vertex against the world, view, and projection matrices.
	output.position = mul(input.position, view_proj_mat);
	output.slice_id = 0;

	return output;
}