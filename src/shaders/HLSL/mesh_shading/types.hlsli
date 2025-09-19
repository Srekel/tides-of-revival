#ifndef _MESH_SHADING_TYPES_HLSLI_
#define _MESH_SHADING_TYPES_HLSLI_

struct Frame
{
    float4x4 view;
    float4x4 projection;
    float4x4 view_proj;
    float4x4 inv_view_proj;
    float4 viewport_info; // xy: size, zw: inv_size
    float4 camera_position;
    float camera_near_plane;
    float camera_far_plane;
    float time;
    uint _padding0;
    // Default samplers
    // TODO: Add more default samplers
    uint linear_repeat_sampler_index;
    uint linear_clamp_sampler_index;
    uint shadow_sampler_index;
    uint shadow_pcf_sampler_index;

    uint vertex_buffer_index;
    uint material_buffer_index;
    uint instance_buffer_index;
    uint meshes_buffer_index;

    uint instances_count;
    uint3 _padding;
};

struct Mesh
{
	uint data_buffer_index;
	uint positions_offset;
	uint normals_offset;
	uint texcoords_offset;
	uint indices_offset;
	uint index_byte_size;
	uint meshlet_offset;
	uint meshlet_vertex_offset;
	uint meshlet_triangle_offset;
	uint meshlet_bounds_offset;
	uint meshlet_count;
};

struct Meshlet
{
    uint vertex_offset;
    uint triangle_offset;
    uint vertex_count;
    uint triangle_count;
};

struct MeshletTriangle
{
    uint v0 : 10;
    uint v1 : 10;
    uint v2 : 10;
    uint _pad : 2;
};

struct MeshletBounds
{
    float3 local_center;
    float3 local_extents;
};

struct MeshletCandidate
{
    uint instance_id;
    uint meshlet_index;
};

struct Instance
{
    float4x4 world;
    float3 local_bounds_origin;
    uint _pad0;
    float3 local_bounds_extents;
    uint id;
    uint mesh_index;
    uint material_index;
    uint2 _pad1;
};

struct Transform
{
    // TODO: Change this to float4x3
    float4x4 world;
};

struct MaterialData
{
    uint albedo_texture_index;
    uint albedo_sampler_index;
    uint normal_texture_index;
    uint normal_sampler_index;
    float4 base_color;
    uint rasterizer_bin;
    uint3 _pad0;
};

#endif // _MESH_SHADING_TYPES_HLSLI_