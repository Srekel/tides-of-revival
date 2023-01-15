#include "common.hlsli"
#include "pbr.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_ALL), " /* index 0 */ \
    "CBV(b1, visibility = SHADER_VISIBILITY_ALL)"   /* index 1 */

struct DrawConst {
    float4x4 object_to_world;
    float4 basecolor_roughness;
    int vertex_offset;
    uint vertex_buffer_index;
};

struct FrameConst {
    float4x4 world_to_clip;
    float3 camera_position;
    float time;
    uint padding1;
    uint padding2;
    uint padding3;
    uint light_count;
    float4 light_positions[MAX_LIGHTS];
    float4 light_radiances[MAX_LIGHTS];
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);

struct VertexOut {
    float4 position_vs : SV_Position;
    float3 position : TEXCOORD0;
    float3 normal : NORMAL;
};

[RootSignature(ROOT_SIGNATURE)]
VertexOut vsTerrain(float3 position : POSITION, float3 normal : _Normal) {
    VertexOut output = (VertexOut)0;

    const float4x4 object_to_clip = mul(cbv_draw_const.object_to_world, cbv_frame_const.world_to_clip);
    output.position_vs = mul(float4(position, 1.0), object_to_clip);
    output.position = mul(float4(position, 1.0), cbv_draw_const.object_to_world).xyz;
    output.normal = normal; // object-space normal

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psTerrain(VertexOut input, out float4 out_color : SV_Target0) {
    float3 colors[5] = {
        float3(0.0, 0.1, 0.7),
        float3(1.0, 1.0, 0.0),
        float3(0.3, 0.8, 0.2),
        float3(0.7, 0.7, 0.7),
        float3(0.95, 0.95, 0.95),
    };

    float3 n = normalize(input.normal);
    float3 base_color = colors[0];
    base_color = lerp(base_color, colors[1], step(0.005, input.position.y * 0.01));
    base_color = lerp(base_color, colors[2], step(0.02, input.position.y * 0.01));
    base_color = lerp(base_color, colors[3], step(1.0, input.position.y * 0.01 + 0.5 * (1.0 - dot(n, float3(0.0, 1.0, 0.0))) ));
    base_color = lerp(base_color, colors[4], step(3.5, input.position.y * 0.01 + 1.5 * dot(n, float3(0.0, 1.0, 0.0)) ));

    PBRInput pbrInput;
    pbrInput.view_position = cbv_frame_const.camera_position;
    pbrInput.position = input.position;
    pbrInput.normal = input.normal;
    pbrInput.roughness = cbv_draw_const.basecolor_roughness.a;
    pbrInput.time = cbv_frame_const.time;

    float3 color = pbrShading(base_color, pbrInput, cbv_frame_const.light_positions, cbv_frame_const.light_radiances, cbv_frame_const.light_count);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;
}
