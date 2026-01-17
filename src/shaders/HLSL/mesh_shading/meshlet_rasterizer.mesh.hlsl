#include "../../FSL/d3d.h"
#include "defines.hlsli"
#include "meshlet_rasterizer_resources.hlsli"

[outputtopology("triangle")]
    [numthreads(MESHLET_THREADS_COUNT, 1, 1)] void
    main(
        in uint GTid : SV_GroupIndex,
        in uint Gid : SV_GroupID,
        out vertices VertexAttribute verts[MESHLET_MAX_VERTICES],
        out indices uint3 triangles[MESHLET_MAX_TRIANGLES],
        out primitives PrimitiveAttribute primitives[MESHLET_MAX_TRIANGLES])
{
    ByteAddressBuffer meshletBinDataBuffer = ResourceDescriptorHeap[g_RasterizerParams.meshletBinDataBufferIndex];
    ByteAddressBuffer binnedMeshletsBuffer = ResourceDescriptorHeap[g_RasterizerParams.binnedMeshletsBufferIndex];
    ByteAddressBuffer visibleMeshletBuffer = ResourceDescriptorHeap[g_RasterizerParams.visibleMeshletsBufferIndex];
    ByteAddressBuffer meshesBuffer = ResourceDescriptorHeap[g_Frame.meshesBufferIndex];

    uint meshletIndex = Gid;
    meshletIndex += meshletBinDataBuffer.Load<uint4>(g_RasterizerParams.binIndex * sizeof(uint4)).w; // Offset
    meshletIndex = binnedMeshletsBuffer.Load<uint>(meshletIndex * sizeof(uint));

    MeshletCandidate candidate = visibleMeshletBuffer.Load<MeshletCandidate>(meshletIndex * sizeof(MeshletCandidate));
    Instance instance = getInstance(candidate.instanceId);
    Mesh mesh = meshesBuffer.Load<Mesh>(candidate.meshIndex * sizeof(Mesh));
    ByteAddressBuffer dataBuffer = ResourceDescriptorHeap[NonUniformResourceIndex(mesh.dataBufferIndex)];
    Meshlet meshlet = dataBuffer.Load<Meshlet>(candidate.meshletIndex * sizeof(Meshlet) + mesh.meshletOffset);

    SetMeshOutputCounts(meshlet.vertexCount, meshlet.triangleCount);

    for (uint i = GTid; i < meshlet.vertexCount; i += MESHLET_THREADS_COUNT)
    {
        uint vertex_id = dataBuffer.Load<uint>((i + meshlet.vertexOffset) * sizeof(uint) + mesh.meshletVertexOffset);
        VertexAttribute attribute = FetchVertexAttribute(mesh, instance.world, vertex_id);
        verts[i] = attribute;
    }

    for (uint i = GTid; i < meshlet.triangleCount; i += MESHLET_THREADS_COUNT)
    {
        MeshletTriangle tri = dataBuffer.Load<MeshletTriangle>((i + meshlet.triangleOffset) * sizeof(MeshletTriangle) + mesh.meshletTriangleOffset);
        triangles[i] = uint3(tri.v0, tri.v1, tri.v2);

        PrimitiveAttribute attribute;
        attribute.primitiveId = i;
        attribute.candidateIndex = meshletIndex;
        primitives[i] = attribute;
    }
}