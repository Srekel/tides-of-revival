#include "common.hlsli"

// TODO: Split the static sampler declarations and move them to common.hlsli
#define ROOT_SIGNATURE \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0), " \
    "CBV(b1), " \
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

struct DrawConst {
    uint start_instance_location;
    int vertex_offset;
    uint vertex_buffer_index;
    uint instance_data_buffer_index;
    uint terrain_layers_buffer_index;
    float terrain_height;
    float heightmap_texel_size;
};

struct InstanceData {
    float4x4 object_to_world;
    uint heightmap_index;
    uint splatmap_index;
    uint lod;
    uint padding1;
};

struct TerrainLayerTextureIndices {
    uint diffuse_index;
    uint normal_index;
    uint arm_index;
    uint padding;
};

ConstantBuffer<DrawConst> cbv_draw_const : register(b0);
ConstantBuffer<FrameConst> cbv_frame_const : register(b1);

struct InstancedVertexOut {
    float4 position_vs : SV_Position;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
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
    float height = heightmap.SampleLevel(sam_linear_clamp, uv, 0).r;

    float3 displaced_position = vertex.position;
    displaced_position.y = height;

    const float4x4 object_to_clip = mul(instance.object_to_world, cbv_frame_const.view_projection);
    output.position_vs = mul(float4(displaced_position, 1.0), object_to_clip);
    output.position = mul(float4(displaced_position, 1.0), instance.object_to_world).xyz;

    output.normal = mul(vertex.normal, (float3x3)instance.object_to_world);
    output.tangent = mul(vertex.tangent.xyz, (float3x3)instance.object_to_world);
    output.uv = uv;

    return output;
}

[RootSignature(ROOT_SIGNATURE)]
GBufferTargets psTerrainQuadTree(InstancedVertexOut input/*, float3 barycentrics : SV_Barycentrics */) {
    ByteAddressBuffer instance_data_buffer = ResourceDescriptorHeap[cbv_draw_const.instance_data_buffer_index];
    uint instance_index = input.instanceID + cbv_draw_const.start_instance_location;
    InstanceData instance = instance_data_buffer.Load<InstanceData>(instance_index * sizeof(InstanceData));

    float3 normal = normalize(input.normal);
    float3 tangent = input.tangent;
    float2 uv = input.uv;

    // Derive normals from the heightmap using the central differences method
    {
        Texture2D heightmap = ResourceDescriptorHeap[instance.heightmap_index];

        // NOTE(gmodarelli): We're changing the epsilon value based on the mesh LOD,
        // otherwise two different neighbouring LODs would have quite different normal values
        float2 e = float2(cbv_draw_const.heightmap_texel_size * pow(2, instance.lod), 0.0);
        float l = heightmap.SampleLevel(sam_linear_clamp, saturate(uv - e.xy), 0).r / cbv_draw_const.terrain_height;
        float r = heightmap.SampleLevel(sam_linear_clamp, saturate(uv + e.xy), 0).r / cbv_draw_const.terrain_height;
        float b = heightmap.SampleLevel(sam_linear_clamp, saturate(uv - e.yx), 0).r / cbv_draw_const.terrain_height;
        float t = heightmap.SampleLevel(sam_linear_clamp, saturate(uv + e.yx), 0).r / cbv_draw_const.terrain_height;
        normal = normalize(float3(l - r, 2.0 * e.x, b - t));

        // Recalculating the tangent now that the normal has been adjusted.
        float3 tmp = normalize(cross(normal, tangent));
        tangent = normalize(cross(normal, tmp));
    }

    // Compute TBN matrix
    float3x3 TBN = makeTBN(normal, tangent);

    Texture2D splatmap = ResourceDescriptorHeap[instance.splatmap_index];
    uint splatmap_index = uint(splatmap.Sample(sam_linear_clamp, uv).r * 255);

    ByteAddressBuffer terrain_layers_buffer = ResourceDescriptorHeap[cbv_draw_const.terrain_layers_buffer_index];
    TerrainLayerTextureIndices terrain_layers = terrain_layers_buffer.Load<TerrainLayerTextureIndices>(splatmap_index * sizeof(TerrainLayerTextureIndices));
    Texture2D diffuse_texture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.diffuse_index)];
    Texture2D normal_texture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.normal_index)];
    Texture2D arm_texture = ResourceDescriptorHeap[NonUniformResourceIndex(terrain_layers.arm_index)];

    // NOTE: We're using world space UV's so we don't end up with seams when we tile or between different LOD's
    float2 world_space_uv = input.position.xz * 0.1;

    float3 albedo = diffuse_texture.Sample(sam_linear_wrap, world_space_uv).rgb;
    albedo.rgb = degamma(albedo.rgb);

    float3 n = normalize(unpack(normal_texture.Sample(sam_linear_wrap, world_space_uv).rgb));
    n = mul(n, TBN);

    float3 arm = arm_texture.Sample(sam_linear_wrap, world_space_uv).rgb;
    float roughness = arm.g;
    float metallic = arm.b;
    float occlusion = arm.r;
    float emission = 0.0;

    GBufferTargets gbuffer;
    gbuffer.albedo = float4(albedo.rgb, 1.0);
    gbuffer.normal = float4(packNormal(n), 0.0);
    gbuffer.material = float4(roughness, metallic, emission, occlusion);
    gbuffer.scene_color = float4(0.0, 0.0, 0.0, 0.0);

    return gbuffer;
}