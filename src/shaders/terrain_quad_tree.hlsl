#include "common.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP)"

struct Vertex {
    float3 position;
    float3 normal;
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
    uint heightmap_index;
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

SamplerState sam_aniso : register(s0);

[RootSignature(ROOT_SIGNATURE)]
InstancedVertexOut vsTerrainQuadTree(uint vertex_id : SV_VertexID, uint instanceID : SV_InstanceID) {
    InstancedVertexOut output = (InstancedVertexOut)0;
    output.instanceID = instanceID;

    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_draw_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_draw_const.vertex_offset) * sizeof(Vertex));

    ByteAddressBuffer instance_transform_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_transform_buffer_index];
    uint instance_index = instanceID + cbv_draw_const.start_instance_location;
    InstanceTransform instance = instance_transform_buffer.Load<InstanceTransform>(instance_index * sizeof(InstanceTransform));

    // ByteAddressBuffer instance_material_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_material_buffer_index];
    // InstanceMaterial material = instance_material_buffer.Load<InstanceMaterial>(instance_index * sizeof(InstanceMaterial));
    // Texture2D heightmap = ResourceDescriptorHeap[material.heightmap_index];
    // float height = heightmap.SampleLevel(sam_aniso, vertex.uv, 0).r;

    float3 displaced_position = vertex.position;
    // displaced_position.y = height * 40.0f;    // TODO: Pass max height to shader

    const float4x4 object_to_clip = mul(instance.object_to_world, cbv_frame_const.world_to_clip);
    output.position_vs = mul(float4(displaced_position, 1.0), object_to_clip);
    output.position = mul(float4(displaced_position, 1.0), instance.object_to_world).xyz;
    output.uv = vertex.uv;

    return output;
}

static const float g_wireframe_smoothing = 1.0;
static const float g_wireframe_thickness = 0.25;

[RootSignature(ROOT_SIGNATURE)]
void psTerrainQuadTree(InstancedVertexOut input, float3 barycentrics : SV_Barycentrics, out float4 out_color : SV_Target0) {
    float3 color = float3(input.uv, 0.0);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;
 
    // wireframe
    float3 barys = barycentrics;
    barys.z = 1.0 - barys.x - barys.y;
    float3 deltas = fwidth(barys);
    float3 smoothing = deltas * g_wireframe_smoothing;
    float3 thickness = deltas * g_wireframe_thickness;
    barys = smoothstep(thickness, thickness + smoothing, barys);
    float min_bary = min(barys.x, min(barys.y, barys.z));

    // TODO: Pass a flag to the shader to control if we want to 
    // render the wireframe or not
    color = lerp(float3(0.3, 0.3, 0.3), color, min_bary);
    min_bary = 1.0;

    out_color = float4(min_bary * color, 1.0);
}