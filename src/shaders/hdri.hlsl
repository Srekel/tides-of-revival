#include "common.hlsli"
#include "random.hlsli"
#include "pbr.hlsli"

struct Const {
    float4x4 object_to_clip;
    uint vertex_buffer_index;
    uint vertex_offset;
};

ConstantBuffer<Const> cbv_const : register(b0);

#if defined(PSO__GENERATE_ENV_TEXTURE)

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(s0, visibility = SHADER_VISIBILITY_PIXEL)"

Texture2D srv_equirect_texture : register(t0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
void vsGenerateEnvTexture(
    uint vertex_id : SV_VertexID,
    out float4 out_position_clip : SV_Position,
    out float3 out_position : _Position
) {
    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_const.vertex_offset) * sizeof(Vertex));

    out_position_clip = mul(float4(vertex.position, 1.0), cbv_const.object_to_clip);
    out_position = vertex.position; // Position in object space.
}

float2 sampleSphericalMap(float3 v) {
    float2 uv = float2(atan2(v.z, v.x), asin(v.y));
    uv *= float2(0.1591, 0.3183);
    uv += 0.5;
    return uv;
}

[RootSignature(root_signature)]
void psGenerateEnvTexture(
    float4 position_ndc : SV_Position,
    float3 position : _Position,
    out float4 out_color : SV_Target0
) {
    const float2 uv = sampleSphericalMap(normalize(position));
    float3 color = srv_equirect_texture.SampleLevel(sam_s0, uv, 0).rgb;
    out_color = float4(color, 1.0);
}

#elif defined(PSO__SAMPLE_ENV_TEXTURE)

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(" \
    "   s0, " \
    "   filter = FILTER_MIN_MAG_MIP_LINEAR, " \
    "   visibility = SHADER_VISIBILITY_PIXEL, " \
    "   addressU = TEXTURE_ADDRESS_CLAMP, " \
    "   addressV = TEXTURE_ADDRESS_CLAMP, " \
    "   addressW = TEXTURE_ADDRESS_CLAMP" \
    ")"

TextureCube srv_env_texture : register(t0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
void vsSampleEnvTexture(
    uint vertex_id : SV_VertexID,
    out float4 out_position_clip : SV_Position,
    out float3 out_uvw : _Uvw
) {
    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_const.vertex_offset) * sizeof(Vertex));

    out_position_clip = mul(float4(vertex.position, 1.0), cbv_const.object_to_clip).xyww;
    out_uvw = vertex.position;
}

[RootSignature(root_signature)]
void psSampleEnvTexture(
    float4 position_clip : SV_Position,
    float3 uvw : _Uvw,
    out float4 out_color : SV_Target0
) {
    float3 env_color = srv_env_texture.Sample(sam_s0, uvw).rgb;
    env_color = env_color / (env_color + 1.0);
    out_color = float4(pow(env_color, 1.0 / GAMMA), 1.0);
}

#elif defined(PSO__GENERATE_IRRADIANCE_TEXTURE)

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(" \
    "   s0, " \
    "   filter = FILTER_MIN_MAG_MIP_LINEAR, " \
    "   visibility = SHADER_VISIBILITY_PIXEL, " \
    "   addressU = TEXTURE_ADDRESS_CLAMP, " \
    "   addressV = TEXTURE_ADDRESS_CLAMP, " \
    "   addressW = TEXTURE_ADDRESS_CLAMP" \
    ")"

TextureCube srv_env_texture : register(t0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
void vsGenerateIrradianceTexture(
    uint vertex_id : SV_VertexID,
    out float4 out_position_clip : SV_Position,
    out float3 out_position : _Position
) {
    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_const.vertex_offset) * sizeof(Vertex));

    out_position_clip = mul(float4(vertex.position, 1.0), cbv_const.object_to_clip);
    out_position = vertex.position;
}

[RootSignature(root_signature)]
void psGenerateIrradianceTexture(
    float4 position_clip : SV_Position,
    float3 position : _Position,
    out float4 out_color : SV_Target0
) {
    const float3 n = normalize(position);

    // This is Right-Handed coordinate system and works for upper-left UV coordinate systems.
    const float3 up_vector = abs(n.y) < 0.999 ? float3(0.0, 1.0, 0.0) : float3(0.0, 0.0, 1.0);
    const float3 tangent_x = normalize(cross(up_vector, n));
    const float3 tangent_y = normalize(cross(n, tangent_x));

    uint num_samples = 0;
    float3 irradiance = 0.0;

    for (float phi = 0.0; phi < (2.0 * PI); phi += 0.025) {
        for (float theta = 0.0; theta < (0.5 * PI); theta += 0.025) {
            // Point on a hemisphere.
            const float3 h = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));

            // Transform from tangent space to world space.
            const float3 sample_vector = tangent_x * h.x + tangent_y * h.y + n * h.z;

            irradiance += srv_env_texture.SampleLevel(sam_s0, sample_vector, 0).rgb *
                cos(theta) * sin(theta);

            num_samples++;
        }
    }

    irradiance = PI * irradiance * (1.0 / num_samples);
    out_color = float4(irradiance, 1.0);
}

#elif defined(PSO__GENERATE_PREFILTERED_ENV_TEXTURE)

#define root_signature \
    "RootFlags(CBV_SRV_UAV_HEAP_DIRECTLY_INDEXED), " \
    "CBV(b0, visibility = SHADER_VISIBILITY_VERTEX), " \
    "RootConstants(b1, num32BitConstants = 1, visibility = SHADER_VISIBILITY_PIXEL), " \
    "DescriptorTable(SRV(t0), visibility = SHADER_VISIBILITY_PIXEL), " \
    "StaticSampler(" \
    "   s0, " \
    "   filter = FILTER_MIN_MAG_MIP_LINEAR, " \
    "   visibility = SHADER_VISIBILITY_PIXEL, " \
    "   addressU = TEXTURE_ADDRESS_CLAMP, " \
    "   addressV = TEXTURE_ADDRESS_CLAMP, " \
    "   addressW = TEXTURE_ADDRESS_CLAMP" \
    ")"

struct RootConst {
    float roughness;
};
ConstantBuffer<RootConst> cbv_root_const : register(b1);

TextureCube srv_env_texture : register(t0);
SamplerState sam_s0 : register(s0);

[RootSignature(root_signature)]
void vsGeneratePrefilteredEnvTexture(
    uint vertex_id : SV_VertexID,
    out float4 out_position_clip : SV_Position,
    out float3 out_position : _Position
) {
    ByteAddressBuffer vertex_buffer = ResourceDescriptorHeap[cbv_const.vertex_buffer_index];
    Vertex vertex = vertex_buffer.Load<Vertex>((vertex_id + cbv_const.vertex_offset) * sizeof(Vertex));

    out_position_clip = mul(float4(vertex.position, 1.0), cbv_const.object_to_clip);
    out_position = vertex.position;
}

[RootSignature(root_signature)]
void psGeneratePrefilteredEnvTexture(
    float4 position_clip : SV_Position,
    float3 position : _Position,
    out float4 out_color : SV_Target0
) {
    const float roughness = cbv_root_const.roughness;
    const float3 n = normalize(position);
    const float3 r = n;
    const float3 v = r;

    float3 prefiltered_color = 0.0;
    float total_weight = 0.0;
    const uint num_samples = 1024;

    for (uint sample_idx = 0; sample_idx < num_samples; ++sample_idx) {
        const float2 xi = hammersley(sample_idx, num_samples);
        const float3 h = importanceSampleGgx(xi, roughness, n);
        const float3 l = normalize(2.0 * dot(v, h) * h - v);
        const float n_dot_l = saturate(dot(n, l));
        if (n_dot_l > 0.0) {
            prefiltered_color += srv_env_texture.SampleLevel(sam_s0, l, 0).rgb * n_dot_l;
            total_weight += n_dot_l;
        }
    }
    out_color = float4(prefiltered_color / max(total_weight, 0.001), 1.0);
}

#endif