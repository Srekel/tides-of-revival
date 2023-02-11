#include "common.hlsli"
#include "pbr.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT | CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), "

struct Vertex {
    float3 position;
    float3 normal;
    float2 uv;
    float4 tangent;
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
    uint padding1;
    uint padding2;
    uint padding3;
    uint light_count;
    float4 light_positions[MAX_LIGHTS];
    float4 light_radiances[MAX_LIGHTS];
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
    float3 normal : NORMAL;
    uint instanceID: SV_InstanceID;
};

[RootSignature(ROOT_SIGNATURE)]
InstancedVertexOut vsInstanced(uint vertex_id : SV_VertexID, uint instanceID : SV_InstanceID) {
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
    output.normal = vertex.normal; // object-space normal

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psInstanced(InstancedVertexOut input, out float4 out_color : SV_Target0) {
    ByteAddressBuffer instance_material_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_material_buffer_index];
    uint instance_index = input.instanceID + cbv_draw_const.start_instance_location;
    InstanceMaterial material = instance_material_buffer.Load<InstanceMaterial>(instance_index * sizeof(InstanceMaterial));

    float3 base_color = material.basecolor_roughness.rgb;

    PBRInput pbrInput;
    pbrInput.view_position = cbv_frame_const.camera_position;
    pbrInput.position = input.position;
    pbrInput.normal = input.normal;
    pbrInput.roughness = material.basecolor_roughness.a;
    pbrInput.time = cbv_frame_const.time;

    float3 color = pbrShading(base_color, pbrInput, cbv_frame_const.light_positions, cbv_frame_const.light_radiances, cbv_frame_const.light_count);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;
}