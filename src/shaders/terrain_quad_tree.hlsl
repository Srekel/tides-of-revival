#include "common.hlsli"
#include "pbr.hlsli"

// TODO: Split the static sampler declarations and move them to common.hlsli
#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s1, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_WRAP, addressV = TEXTURE_ADDRESS_WRAP, addressW = TEXTURE_ADDRESS_WRAP), " \
    "StaticSampler(s2, filter = FILTER_COMPARISON_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s3, filter = FILTER_COMPARISON_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_WRAP, addressV = TEXTURE_ADDRESS_WRAP, addressW = TEXTURE_ADDRESS_WRAP)"

SamplerState sam_aniso_clamp : register(s0);
SamplerState sam_aniso_wrap : register(s1);
SamplerState sam_linear_clamp : register(s2);
SamplerState sam_linear_wrap : register(s3);

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
    uint heightmap_index;
    uint splatmap_index;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);

struct InstancedVertexOut {
    float4 position_vs : SV_Position;
    float3 normal : NORMAL;
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

    ByteAddressBuffer instance_material_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_material_buffer_index];
    InstanceMaterial material = instance_material_buffer.Load<InstanceMaterial>(instance_index * sizeof(InstanceMaterial));
    Texture2D heightmap = ResourceDescriptorHeap[material.heightmap_index];
    float height = heightmap.SampleLevel(sam_linear_clamp, vertex.uv, 0).r;

    float3 displaced_position = vertex.position;
    displaced_position.y = lerp(0.0f, 200.0f, height);    // TODO: Pass min/max heights to shader

    const float4x4 object_to_clip = mul(instance.object_to_world, cbv_frame_const.world_to_clip);
    output.position_vs = mul(float4(displaced_position, 1.0), object_to_clip);
    output.position = mul(float4(displaced_position, 1.0), instance.object_to_world).xyz;

    output.normal = vertex.normal;
    output.uv = vertex.uv;

    return output;
}

static const float g_wireframe_smoothing = 1.0;
static const float g_wireframe_thickness = 0.25;
static const float2 texel = 1.0f / float2(65.0f, 65.0f);

[RootSignature(ROOT_SIGNATURE)]
void psTerrainQuadTree(InstancedVertexOut input/*, float3 barycentrics : SV_Barycentrics*/, out float4 out_color : SV_Target0) {
    float3 base_colors[5] = {
        float3(0.0, 0.1, 0.7),
        float3(1.0, 1.0, 0.0),
        float3(0.3, 0.8, 0.2),
        float3(0.7, 0.7, 0.7),
        float3(0.95, 0.95, 0.95),
    };

    float3 normal = normalize(input.normal);

    // Derive normals from the heightmap 
    // https://www.shadertoy.com/view/3sSSW1
    {
        uint instance_index = input.instanceID + cbv_draw_const.start_instance_location;
        ByteAddressBuffer instance_material_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_material_buffer_index];
        InstanceMaterial material = instance_material_buffer.Load<InstanceMaterial>(instance_index * sizeof(InstanceMaterial));
        Texture2D heightmap = ResourceDescriptorHeap[material.heightmap_index];

        float height = heightmap.Sample(sam_linear_clamp, input.uv).r;
        float height_h = heightmap.Sample(sam_linear_clamp, input.uv + texel * float2(1.0, 0.0)).r; 
        float height_v = heightmap.Sample(sam_linear_clamp, input.uv + texel * float2(0.0, 1.0)).r; 
        float2 n = height - float2(height_h, height_v);
        n *= 20.0;
        n += 0.5;
        normal = normalize(float3(n.xy, 1.0));
    }

    float3 base_color = base_colors[0];
    base_color = lerp(base_color, base_colors[1], step(0.005, input.position.y * 0.01));
    base_color = lerp(base_color, base_colors[2], step(0.02, input.position.y * 0.01));
    base_color = lerp(base_color, base_colors[3], step(1.0, input.position.y * 0.01 + 0.5 * (1.0 - dot(normal, float3(0.0, 1.0, 0.0))) ));
    base_color = lerp(base_color, base_colors[4], step(3.5, input.position.y * 0.01 + 1.5 * dot(normal, float3(0.0, 1.0, 0.0)) ));

    PBRInput pbrInput;
    pbrInput.view_position = cbv_frame_const.camera_position;
    pbrInput.position = input.position;
    pbrInput.normal = normal;
    pbrInput.roughness = 0.5f;
    pbrInput.time = cbv_frame_const.time;

    float3 color = pbrShading(base_color, pbrInput, cbv_frame_const.light_positions, cbv_frame_const.light_radiances, cbv_frame_const.light_count);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;
 
    // TODO: Pass a flag to the shader to control if we want to 
    // render the wireframe or not
    // wireframe
    // float3 barys = barycentrics;
    // barys.z = 1.0 - barys.x - barys.y;
    // float3 deltas = fwidth(barys);
    // float3 smoothing = deltas * g_wireframe_smoothing;
    // float3 thickness = deltas * g_wireframe_thickness;
    // barys = smoothstep(thickness, thickness + smoothing, barys);
    // float min_bary = min(barys.x, min(barys.y, barys.z));

    // color = lerp(float3(0.3, 0.3, 0.3), color, min_bary);
    // min_bary = 1.0;

    // out_color = float4(min_bary * color, 1.0);
}