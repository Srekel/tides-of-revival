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
    float2(0.0, 0.0),
    float2(1.0, 1.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0)
};

struct Const {
    float4x4 screen_to_clip;
    uint ui_transform_buffer_index;
};

struct UITransform {
    float4 rect;
    float4 color;
    uint texture_index;
    float3 _padding;
};

struct VertexOut {
    float4 position_vs : SV_Position;
    float2 uv : TEXCOORD0;
    uint instanceID: SV_InstanceID;
};

ConstantBuffer<Const> cbv_const : register(b0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
VertexOut vsUI(uint vertex_id : SV_VertexID, uint instanceID : SV_InstanceID)
{
    VertexOut output = (VertexOut)0;
    output.instanceID = instanceID;

    uint2 quad_vertex_position = quad_vertex_positions[vertex_id];

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[cbv_const.ui_transform_buffer_index];
    UITransform instance = instance_transform_buffer.Load<UITransform>(instanceID * sizeof(UITransform));

    float2 position = float2(instance.rect[quad_vertex_position.x], instance.rect[quad_vertex_position.y]);
    float2 uv = quad_vertex_uvs[vertex_id];

    output.position_vs = mul(cbv_const.screen_to_clip, float4(position, 0.0f, 1.0f));
    output.uv = uv;

    return output;
}

[RootSignature(root_signature)]
float4 psUI(VertexOut input) : SV_Target
{
    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[cbv_const.ui_transform_buffer_index];
    UITransform instance = instance_transform_buffer.Load<UITransform>(input.instanceID * sizeof(UITransform));

    Texture2D texture = ResourceDescriptorHeap[instance.texture_index];
    float4 color = texture.SampleLevel(sam_s0, input.uv, 0);
    color *= instance.color;
    return color;
}
