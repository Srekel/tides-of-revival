// Based on https://github.com/sebh/UnrealEngineSkyAtmosphere

#include "common.hlsli"

[maxvertexcount(3)]
void main(triangle VertexOutput input[3], inout TriangleStream<GeometryOutput> gsout)
{
	GeometryOutput output;
	for (uint i = 0; i < 3; i++)
	{
		output.position = input[i].position;
		output.slice_id = input[0].slice_id;
		gsout.Append(output);
	}
	gsout.RestartStrip();
}