#define DIRECT3D12
#define STAGE_VERT

#include "skybox_resources.hlsli"

VSOutput VS_MAIN(VSInput Input)
{
    INIT_MAIN;
    VSOutput result;
    result.Position = mul(g_proj_view_mat, Input.Position);
    result.Position = result.Position.xyww; // this makes depth buffer 1.0

    result.pos = Input.Position.xyz;
    RETURN(result);
}
