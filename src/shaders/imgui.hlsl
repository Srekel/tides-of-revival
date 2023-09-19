#define root_signature \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_PIXEL)"

struct Const {
    float4x4 screen_to_clip;
};
ConstantBuffer<Const> cbv_const : register(b0);
Texture2D srv_t0 : register(t0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
void vsImGui(
    float2 position : POSITION,
    float2 uv : _Uv,
    float4 color : _Color,
    out float4 out_position : SV_Position,
    out float2 out_uv : _Uv,
    out float4 out_color : _Color
) {
    out_position = mul(cbv_const.screen_to_clip, float4(position, 0.0f, 1.0f));
    out_uv = uv;
    out_color = color;
}

[RootSignature(root_signature)]
void psImGui(
    float4 position : SV_Position,
    float2 uv : _Uv,
    float4 color : _Color,
    out float4 out_color : SV_Target0
) {
    out_color = color * srv_t0.Sample(sam_s0, uv);
}