#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), "

struct Vertex {
    float3 position;
    float2 uv;
};

struct DrawConst {
    uint start_instance_location;
    int vertex_offset;
    uint vertex_buffer_index;
    uint instance_transform_buffer_index;
    uint instance_material_buffer_index;
};

struct FrameConst {
    float4x4 world_to_clip;
    float3 camera_position;
    float time;
};

struct InstanceTransform {
    float4x4 object_to_world;
};

struct InstanceMaterial {
    float4 basecolor_roughness;
};

// ConstantBuffer<DrawConst> cbv_draw_const : register(b0, per_object_space);
// ConstantBuffer<FrameConst> cbv_frame_const : register(b0, per_pass_space);
ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);

struct InstancedVertexOut {
    float4 position_vs : SV_Position;
    float3 position : TEXCOORD0;
    float2 uv : TEXCOORD1;
    uint instanceID: SV_InstanceID;
};

[RootSignature(ROOT_SIGNATURE)]
InstancedVertexOut vsTerrainQuadTree(uint vertex_id : SV_VertexID, uint instanceID : SV_InstanceID) {
    InstancedVertexOut output = (InstancedVertexOut)0;
    output.instanceID = instanceID;

    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_draw_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_draw_const.vertex_offset) * sizeof(Vertex));

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_transform_buffer_index];
    uint instance_index = instanceID + cbv_draw_const.start_instance_location;
    InstanceTransform instance = instance_transform_buffer.Load<InstanceTransform>(instance_index * sizeof(InstanceTransform));

    const float4x4 object_to_clip = mul(instance.object_to_world, cbv_frame_const.world_to_clip);
    output.position_vs = mul(float4(vertex.position, 1.0), object_to_clip);
    output.position = mul(float4(vertex.position, 1.0), instance.object_to_world).xyz;
    output.uv = vertex.uv;

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psTerrainQuadTree(InstancedVertexOut input, out float4 out_color : SV_Target0) {
    ByteAddressBuffer instance_material_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_material_buffer_index];
    uint instance_index = input.instanceID + cbv_draw_const.start_instance_location;
    InstanceMaterial material = instance_material_buffer.Load<InstanceMaterial>(instance_index * sizeof(InstanceMaterial));

    float3 base_color = material.basecolor_roughness.rgb;

    float3 color = float3(input.uv, 0.0);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;
}