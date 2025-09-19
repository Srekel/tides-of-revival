#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

[outputtopology("triangle")]
[numthreads(MESHLET_THREADS_COUNT, 1, 1)]
void main
(
    in uint group_thread_id : SV_GroupIndex,
    in uint group_id : SV_GroupID,
    out vertices VertexAttribute verts[MESHLET_MAX_VERTICES],
    out indices uint3 triangles[MESHLET_MAX_TRIANGLES],
    out primitives PrimitiveAttribute primitives[MESHLET_MAX_TRIANGLES]
)
{
    ByteAddressBuffer meshlet_bin_data_buffer = ResourceDescriptorHeap[g_rasterizer_params.meshlet_bin_data_buffer_index];
    ByteAddressBuffer binned_meshlets_buffer = ResourceDescriptorHeap[g_rasterizer_params.binned_meshlets_buffer_index];
    ByteAddressBuffer visible_meshlet_buffer = ResourceDescriptorHeap[g_rasterizer_params.visible_meshlets_buffer_index];
    ByteAddressBuffer mesh_buffer = ResourceDescriptorHeap[g_Frame.meshes_buffer_index];

    uint meshlet_index = group_id;
    meshlet_index += meshlet_bin_data_buffer.Load<uint4>(g_rasterizer_params.bin_index * sizeof(uint4)).w; // Offset
    meshlet_index = binned_meshlets_buffer.Load<uint>(meshlet_index * sizeof(uint));

    MeshletCandidate candidate = visible_meshlet_buffer.Load<MeshletCandidate>(meshlet_index * sizeof(MeshletCandidate));
    Instance instance = getInstance(candidate.instance_id);
    Mesh mesh = mesh_buffer.Load<Mesh>(instance.mesh_index * sizeof(Mesh));
    ByteAddressBuffer data_buffer = ResourceDescriptorHeap[NonUniformResourceIndex(mesh.data_buffer_index)];
    Meshlet meshlet = data_buffer.Load<Meshlet>(candidate.meshlet_index * sizeof(Meshlet) + mesh.meshlet_offset);

    SetMeshOutputCounts(meshlet.vertex_count, meshlet.triangle_count);

    for (uint i = group_thread_id; i < meshlet.vertex_count; i += MESHLET_THREADS_COUNT)
    {
        uint vertex_id = data_buffer.Load<uint>((i + meshlet.vertex_offset) * sizeof(uint) + mesh.meshlet_vertex_offset);
        VertexAttribute attribute = FetchVertexAttribute(mesh, instance.world, vertex_id);
        verts[i] = attribute;
    }

    for (uint i = group_thread_id; i < meshlet.triangle_count; i += MESHLET_THREADS_COUNT)
    {
        MeshletTriangle tri = data_buffer.Load<MeshletTriangle>((i + meshlet.triangle_offset) * sizeof(MeshletTriangle) + mesh.meshlet_triangle_offset);
        triangles[i] = uint3(tri.v0, tri.v1, tri.v2);

        PrimitiveAttribute attribute;
        attribute.primitive_id = i;
        attribute.candidate_index = meshlet_index;
        primitives[i] = attribute;
    }
}