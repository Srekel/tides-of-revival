#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_PIXEL)"

static const uint top = 0;
static const uint bottom = 1;
static const uint left = 2;
static const uint right = 3;

static const uint quad_vertex_count = 4;
static const uint2 quad_vertex_positions[quad_vertex_count] = {
    uint2(left, top),
    uint2(right, bottom),
    uint2(left, bottom),
    uint2(right, top)
};

static const float2 quad_vertex_uvs[quad_vertex_count] = {
    float2(0.0, 1.0),
    float2(1.0, 0.0),
    float2(0.0, 0.0),
    float2(1.0, 1.0)
};

struct Const {
    float4x4 screen_to_clip;
    float4 rect;
    uint texture_index;
    float opacity;
    float2 _padding;
};

struct VertexOut {
    float4 position_vs : SV_Position;
    float2 uv : TEXCOORD0;
};

ConstantBuffer<Const> cbv_const : register(b0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
VertexOut vsUI(uint vertex_id : SV_VertexID)
{
    VertexOut output = (VertexOut)0;

    uint2 quad_vertex_position = quad_vertex_positions[vertex_id];
    float2 position = float2(cbv_const.rect[quad_vertex_position.x], cbv_const.rect[quad_vertex_position.y]);
    float2 uv = quad_vertex_uvs[vertex_id];

    output.position_vs = mul(cbv_const.screen_to_clip, float4(position, 0.0f, 1.0f));
    output.uv = uv;

    return output;
}

[RootSignature(root_signature)]
float4 psUI(VertexOut input) : SV_Target
{
    Texture2D texture = ResourceDescriptorHeap[cbv_const.texture_index];
    float4 color = texture.SampleLevel(sam_s0, input.uv, 0);
    color.a *= cbv_const.opacity;
    return color;
}
