// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere
#include "sky_atmosphere_common.hlsli"

VertexOutput main(uint vertex_id : SV_VertexID, uint instance_id : SV_InstanceID)
{
	VertexOutput output = (VertexOutput)0;

	// For a range on screen in [-0.5,0.5]
	float2 uv = -1.0f;
	uv = vertex_id == 1 ? float2(-1.0f, 3.0f) : uv;
	uv = vertex_id == 2 ? float2( 3.0f,-1.0f) : uv;
	output.position = float4(uv, 0.0f, 1.0f);
	output.slice_id = instance_id;

	return output;
}
