#define DIRECT3D12
#define STAGE_VERT

#include "../FSL/d3d.h"

STRUCT(VsOut)
{
	DATA(float4, Position,  SV_Position);
	DATA(float2, UV, TEXCOORD0);
};

VsOut VS_MAIN(uint VertexID : SV_VertexID)
{
	INIT_MAIN;

	VsOut Out;
    Out.UV = float2((VertexID << 1) & 2, VertexID & 2);
    Out.Position = float4(Out.UV * float2(2, -2) + float2(-1, 1), 0, 1);

	RETURN(Out);
}
