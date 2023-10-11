#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "StaticSampler(s0, filter = FILTER_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_PIXEL)"

struct Vertex {
    float2 position;
    float2 uv;
};

struct VertexOut {
    float4 position_vs : SV_Position;
    float2 uv : TEXCOORD0;
};

struct Const {
    float4x4 screen_to_clip;
    uint vertex_buffer_index;
    uint texture_index;
    float opacity;
};

ConstantBuffer<Const> cbv_const : register(b0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
VertexOut vsUI(uint vertex_id : SV_VertexID)
{
    VertexOut output = (VertexOut)0;

    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>(vertex_id * sizeof(Vertex));

    output.position_vs = mul(cbv_const.screen_to_clip, float4(vertex.position, 0.0f, 1.0f));
    output.uv = vertex.uv;

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
