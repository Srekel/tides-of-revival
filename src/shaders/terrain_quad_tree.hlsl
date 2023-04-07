#include "common.hlsli"
#include "pbr.hlsli"
#include "gbuffer.hlsli"

// TODO: Split the static sampler declarations and move them to common.hlsli
#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
    "CBV(b2), " \
    "StaticSampler(s0, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s1, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_WRAP, addressV = TEXTURE_ADDRESS_WRAP, addressW = TEXTURE_ADDRESS_WRAP), " \
    "StaticSampler(s2, filter = FILTER_COMPARISON_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_CLAMP, addressV = TEXTURE_ADDRESS_CLAMP, addressW = TEXTURE_ADDRESS_CLAMP), " \
    "StaticSampler(s3, filter = FILTER_COMPARISON_MIN_MAG_MIP_LINEAR, visibility = SHADER_VISIBILITY_ALL, addressU = TEXTURE_ADDRESS_WRAP, addressV = TEXTURE_ADDRESS_WRAP, addressW = TEXTURE_ADDRESS_WRAP), " \
    "StaticSampler(s4, filter = FILTER_ANISOTROPIC, maxAnisotropy = 16, visibility = SHADER_VISIBILITY_PIXEL)"

SamplerState sam_aniso_clamp : register(s0);
SamplerState sam_aniso_wrap : register(s1);
SamplerState sam_linear_clamp : register(s2);
SamplerState sam_linear_wrap : register(s3);
SamplerState sam_aniso : register(s4);

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
    uint instance_data_buffer_index;
    uint terrain_layers_buffer_index;
};

struct InstanceData {
    float4x4 object_to_world;
    uint heightmap_index;
    uint splatmap_index;
    uint padding1;
    uint padding2;
};

struct TerrainLayerTextureIndices {
    uint diffuse_index;
    uint normal_index;
    uint arm_index;
    uint padding;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);
ConstantBuffer<SceneConst> cbv_scene_const : register(b2);

struct InstancedVertexOut {
    float4 position_vs : SV_Position;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
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

    ByteAddressBuffer instance_data_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_data_buffer_index];
    uint instance_index = instanceID + cbv_draw_const.start_instance_location;
    InstanceData instance = instance_data_buffer.Load<InstanceData>(instance_index * sizeof(InstanceData));

    Texture2D heightmap = ResourceDescriptorHeap[instance.heightmap_index];
    float2 uv = float2(vertex.uv.x, 1.0 - vertex.uv.y);
    float height = heightmap.SampleLevel(sam_linear_clamp, uv, 0).r;// * 2.0 - 1.0;

    float3 displaced_position = vertex.position;
    // displaced_position.y = cbv_frame_const.noise_scale_y * (height + cbv_frame_const.noise_offset_y);
    displaced_position.y = height;

    const float4x4 object_to_clip = mul(instance.object_to_world, cbv_frame_const.world_to_clip);
    output.position_vs = mul(float4(displaced_position, 1.0), object_to_clip);
    output.position = mul(float4(displaced_position, 1.0), instance.object_to_world).xyz;

    output.normal = vertex.normal;
    output.tangent = vertex.tangent;
    output.uv = uv;

    return output;
}

static const float g_wireframe_smoothing = 1.0;
static const float g_wireframe_thickness = 0.25;
static const float2 texel = 1.0f / float2(65.0f, 65.0f);

[RootSignature(ROOT_SIGNATURE)]
GBufferTargets psTerrainQuadTree(InstancedVertexOut input/*, float3 barycentrics : SV_Barycentrics*/) {
    ByteAddressBuffer instance_data_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_data_buffer_index];
    uint instance_index = input.instanceID + cbv_draw_const.start_instance_location;
    InstanceData instance = instance_data_buffer.Load<InstanceData>(instance_index * sizeof(InstanceData));

    float3 normal = normalize(input.normal);
    float3 tangent = input.tangent.xyz;
    float2 uv = input.uv;

    // Derive normals from the heightmap
    {
        Texture2D heightmap = ResourceDescriptorHeap[instance.heightmap_index];

        float r = heightmap.Sample(sam_linear_clamp, uv + texel * float2( 1.0,  0.0)).r;
        float l = heightmap.Sample(sam_linear_clamp, uv + texel * float2(-1.0,  0.0)).r;
        float t = heightmap.Sample(sam_linear_clamp, uv + texel * float2( 0.0,  1.0)).r;
        float b = heightmap.Sample(sam_linear_clamp, uv + texel * float2( 0.0, -1.0)).r;
        normal = normalize(float3(2.0 * (r - l), 2.0 * (b - t), -4));

        // NOTE: recalculating the tangent now that the normal has been adjusted.
        // I'm not sure this is correct.
        float3 tmp = normalize(cross(normal, tangent));
        tangent = normalize(cross(normal, tmp));
    }

    // Compute TBN matrix
    const float3 bitangent = normalize(cross(normal, tangent)) * input.tangent.w;
    const float3x3 TBN = float3x3(tangent, bitangent, normal);

    Texture2D splatmap = ResourceDescriptorHeap[instance.splatmap_index];
    uint splatmap_index = uint(splatmap.Sample(sam_linear_clamp, uv).r * 255);

    ByteAddressBuffer terrain_layers_buffer = ResourceDescriptorHeap[cbv_draw_const.terrain_layers_buffer_index];
    TerrainLayerTextureIndices terrain_layers = terrain_layers_buffer.Load<TerrainLayerTextureIndices>(splatmap_index * sizeof(TerrainLayerTextureIndices));
    Texture2D diffuse_texture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.diffuse_index)];
    Texture2D normal_texture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.normal_index)];
    Texture2D arm_texture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.arm_index)];
    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    float2 world_space_uv = input.position.xz * 0.1;
    float3 base_color = pow(diffuse_texture.Sample(sam_linear_wrap, world_space_uv).rgb, GAMMA);
    float3 n = normalize(normal_texture.Sample(sam_linear_wrap, world_space_uv).rgb * 2.0 - 1.0);
    n = mul(n, TBN);
    n = normalize(mul(n, (float3x3)instance.object_to_world));
    float3 arm = arm_texture.Sample(sam_linear_wrap, world_space_uv).rgb;

    GBufferTargets gbuffer = (GBufferTargets)0;
    gbuffer.encode_albedo(base_color.rgb);
    gbuffer.encode_normals(n.xyz);
    gbuffer.encode_material(arm.g, arm.b, arm.r);
    return gbuffer;

    /*
    const float3 v = normalize(cbv_frame_const.camera_position - input.position);

    TextureCube<float3> ibl_radiance_texture = ResourceDescriptorHeap[cbv_scene_const.radiance_texture_index];
    TextureCube<float3> ibl_irradiance_texture = ResourceDescriptorHeap[cbv_scene_const.irradiance_texture_index];
    // TextureCube ibl_specular_texture = ResourceDescriptorHeap[cbv_scene_const.specular_texture_index];
    // Texture2D ibl_brdf_integration_texture = ResourceDescriptorHeap[cbv_scene_const.brdf_integration_texture_index];

    float3 lightDirection[3] = {
        float3(0.0, 1.0, 0.0),
        float3(0.0, 1.0, 0.0),
        float3(0.0, 1.0, 0.0),
    };
    float3 lightColor[3] = {
        float3(1.0, 1.0, 1.0),
        float3(1.0, 1.0, 1.0),
        float3(1.0, 1.0, 1.0),
    };

    float3 color = LightSurface(v, n, 1, lightColor, lightDirection, base_color, arm.g, arm.b, arm.r, ibl_radiance_texture, ibl_irradiance_texture, sam_aniso_clamp, 10);
    color = gammaCorrect(color);
    out_color.rgb = color;
    out_color.a = 1;

    // TODO: Pass a flag to the shader to control if we want to
    // render the wireframe or not
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
    */
}