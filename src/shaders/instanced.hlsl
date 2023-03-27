#include "common.hlsli"
#include "pbr.hlsli"

#define ROOT_SIGNATURE \
    "RootFlags(ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT | CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "CBV(b2), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_PIXEL)"

SamplerState sam_aniso : register(s0);

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

struct SceneConst {
    uint irradiance_texture_index;
    uint specular_texture_index;
    uint brdf_integration_texture_index;
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

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);
ConstantBuffer<SceneConst> cbv_scene_const : register(b2);

struct InstancedVertexOut {
    float4 position_vs : SV_Position;
    float3 position : TEXCOORD0;
    float3 normal : NORMAL;
    float3 color : COLOR;
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
    output.color = vertex.color;

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
void psInstanced(InstancedVertexOut input, out float4 out_color : SV_Target0) {
    ByteAddressBuffer instance_material_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_material_buffer_index];
    uint instance_index = input.instanceID + cbv_draw_const.start_instance_location;
    InstanceMaterial material = instance_material_buffer.Load<InstanceMaterial>(instance_index * sizeof(InstanceMaterial));

    float3 base_color = material.basecolor_roughness.rgb;
    base_color = pow(input.color, GAMMA);

    const float3 v = normalize(cbv_frame_const.camera_position - input.position);

    TextureCube ibl_irradiance_texture = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];
    TextureCube ibl_specular_texture = ResourceDescriptorHeap[cbv_scene_const.specular_texture_index];
    Texture2D ibl_brdf_integration_texture = ResourceDescriptorHeap[cbv_scene_const.brdf_integration_texture_index];

    const float3 ibl_irradiance = ibl_irradiance_texture.SampleLevel(sam_aniso, input.normal, 0.0).rgb;

    const float3 r = reflect(-v, input.normal);
    const float3 ibl_specular = ibl_specular_texture.SampleLevel(
        sam_aniso,
        r,
        material.basecolor_roughness.a * 5.0 // roughness * (num_mip_levels - 1.0)
    ).rgb;

    const float n_dot_v = saturate(dot(input.normal, v));
    const float2 ibl_brdf = ibl_brdf_integration_texture.SampleLevel(
        sam_aniso,
        float2(min(n_dot_v, 0.999), material.basecolor_roughness.a),
        0.0
    ).rg;

    PBRInput pbr_input;
    pbr_input.base_color = base_color;
    pbr_input.view_direction = v;
    pbr_input.position = input.position;
    pbr_input.normal = input.normal;
    pbr_input.roughness = material.basecolor_roughness.a;
    pbr_input.metallic = 0.0;
    pbr_input.ao = 1.0;
    pbr_input.ibl_irradiance = ibl_irradiance;
    pbr_input.ibl_specular = ibl_specular;
    pbr_input.ibl_brdf = ibl_brdf;
    pbr_input.time = cbv_frame_const.time;

    float3 color = pbrShading(pbr_input, cbv_frame_const.light_positions, cbv_frame_const.light_radiances, cbv_frame_const.light_count);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;
}