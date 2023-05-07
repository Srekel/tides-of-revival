#include "common.hlsli"
#include "gbuffer.hlsli"

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1)"

struct Const {
    float4x4 object_to_clip;
};

struct Vertex {
    float3 position;
    float3 normal;
    float2 uv;
    float4 tangent;
    float3 color;
};

struct DrawConst {
    uint start_instance_location;
    int vertex_offset;
    uint vertex_buffer_index;
    uint instance_transform_buffer_index;
    uint instance_material_buffer_index;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<Const> cbv_const : register(b1);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
void vsSkybox(
    uint vertex_id : SV_VertexID,
    out float4 out_position_clip : SV_Position,
    out float3 out_uvw : _Uvw
) {
    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_draw_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_draw_const.vertex_offset) * sizeof(Vertex));

    out_position_clip = mul(float4(vertex.position, 1.0), cbv_const.object_to_clip).xyww;
    out_uvw = vertex.position;
}

[RootSignature(root_signature)]
GBufferTargets psSkybox(
    float4 position_clip : SV_Position,
    float3 uvw : _Uvw
) {
    GBufferTargets gbuffer;
    gbuffer.albedo = 0;
    gbuffer.normal = float4(uvw, 0.0);
    gbuffer.material = float4(0.0, 0.0, 0.0, 1.0);

    return gbuffer;
}
