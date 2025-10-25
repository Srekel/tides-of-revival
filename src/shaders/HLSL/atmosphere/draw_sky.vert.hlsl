#define DIRECT3D12
#define STAGE_VERT

#include "draw_sky_resources.hlsli"

VSOutput VS_MAIN(VSInput Input)
{
    INIT_MAIN;
    VSOutput Out;

    float3 position_vs = mul((float3x3)g_view_mat, Input.Position.xyz);
    Out.Position = mul(g_proj_mat, float4(position_vs, 1.0f));
    Out.Position.z = 0.0000001f;
    Out.UV = Input.Position.xyz;
    Out.SunPosition = mul((float3x3)g_sun_mat, Input.Position.xyz);
    Out.MoonPosition = mul((float3x3)g_moon_mat, Input.Position.xyz);
    Out.MoonPosition *= -1.0;

    RETURN(Out);
}