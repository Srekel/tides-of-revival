#include <assert.h>
#define CGLTF_IMPLEMENTATION
#include <cgltf.h>
#include <meshoptimizer.h>
#include <stdint.h>
#include <stdio.h>

static const int MESHLET_MAX_TRIANGLES = 124;
static const int MESHLET_MAX_VERTICES = 64;
static const char MESH_MAGIC[] = { 'T', 'i', 'd', 'e', 's', 'M', 'e', 's', 'h' };

struct float2_t
{
	float x;
	float y;
};

struct float3_t
{
	float x;
	float y;
	float z;
};

struct float4_t
{
	float x;
	float y;
	float z;
	float w;
};

float3_t float3_min(float3_t a, float3_t b)
{
	return
	{
		a.x < b.x ? a.x : b.x,
		a.y < b.y ? a.y : b.y,
		a.z < b.z ? a.z : b.z,
	};
}

float3_t float3_max(float3_t a, float3_t b)
{
	return
	{
		a.x > b.x ? a.x : b.x,
		a.y > b.y ? a.y : b.y,
		a.z > b.z ? a.z : b.z,
	};
}

float3_t operator+(float3_t a, float3_t b)
{
	return
	{
		a.x + b.x,
		a.y + b.y,
		a.z + b.z
	};
}

float3_t operator-(float3_t a, float3_t b)
{
	return
	{
		a.x - b.x,
		a.y - b.y,
		a.z - b.z
	};
}

float3_t operator/(float3_t v, float divisor)
{
	return
	{
		v.x / divisor,
		v.y / divisor,
		v.z / divisor
	};
}

bool operator==(float4_t a, float4_t b)
{
	return a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w;
}

bool operator==(float3_t a, float3_t b)
{
	return a.x == b.x && a.y == b.y && a.z == b.z;
}

bool operator==(float2_t a, float2_t b)
{
	return a.x == b.x && a.y == b.y;
}

struct meshlet_t
{
	uint32_t vertex_offset;
	uint32_t triangle_offset;
	uint32_t vertex_count;
	uint32_t triangle_count;
};

bool operator==(meshlet_t a, meshlet_t b)
{
	return a.vertex_offset == b.vertex_offset &&
		a.triangle_offset == b.triangle_offset &&
		a.vertex_count == b.vertex_count &&
		a.triangle_count == b.triangle_count;
}

struct meshlet_triangle_t
{
	uint32_t v0 : 10;
	uint32_t v1 : 10;
	uint32_t v2 : 10;
	uint32_t : 2;
};

bool operator==(meshlet_triangle_t a, meshlet_triangle_t b)
{
	return a.v0 == b.v0 &&
		a.v1 == b.v1 &&
		a.v2 == b.v2;
}

struct meshlet_bounds_t
{
	float3_t local_center;
	float3_t local_extents;
};

bool operator==(meshlet_bounds_t a, meshlet_bounds_t b)
{
	return a.local_center == b.local_center &&
		a.local_extents == b.local_extents;
}

template<typename T>
struct fixed_array_t
{
	size_t count = 0;
	T* data = nullptr;

	void init(size_t initial_count)
	{
		assert(data == nullptr);
		assert(data == 0);
		count = initial_count;
		data = (T*)malloc(sizeof(T) * count);
		assert(data);
		memset(data, 0, sizeof(T) * count);
	}

	void deinit()
	{
		assert(data);
		free(data);
		data = nullptr;
		count = 0;
	}

	void resize(size_t new_count)
	{
		assert(data);
		assert(count > 0);
		assert(new_count <= count);

		if (new_count <= count)
		{
			count = new_count;
			return;
		}

		// TODO
		
		T* old_data = data;
		data = (T*)malloc(sizeof(T) * new_count);
		assert(data);
		memset(data, 0, sizeof(T) * new_count);
		size_t elements_to_copy = (new_count > count) ? count : new_count;
		errno_t result = memcpy_s(data, sizeof(T) * new_count, old_data, sizeof(T) * elements_to_copy);
		assert(result == 0);
		free(old_data);
		count = new_count;
	}
};

enum mesh_data_flags_e : uint8_t
{
	mesh_data_flag_none = 0x0,
	mesh_data_flag_interleaved = 0x1,
	mesh_data_flag_meshlets = 0x2,
};

struct vertex_data_t
{
	float3_t position;
	float3_t normal;
	float4_t tangent;
	float2_t texcoord0;
};

bool operator==(vertex_data_t a, vertex_data_t b)
{
	return a.position == b.position &&
		a.normal == b.normal &&
		a.tangent == b.tangent &&
		a.texcoord0 == b.texcoord0;
}

struct mesh_data_t
{
	fixed_array_t<uint32_t> indices;
	uint32_t first_index;

	fixed_array_t<vertex_data_t> vertices;
	uint32_t first_vertex;

	fixed_array_t<float3_t> positions_stream;
	fixed_array_t<float3_t> normals_stream;
	fixed_array_t<float3_t> tangents_stream;
	fixed_array_t<float2_t> texcoords_stream;

	fixed_array_t<meshlet_t> meshlets;
	fixed_array_t<uint32_t> meshlet_vertices;
	fixed_array_t<meshlet_triangle_t> meshlet_triangles;
	fixed_array_t<meshlet_bounds_t> meshlet_bounds;
};

struct command_line_arguments_t
{
	char* input_path;
	char* output_path;
	bool mikkt_space_tangents;
	bool generate_meshlets;
	bool interleaved;
};

int main(int argc, char** argv)
{
	printf("Model Converter\n");

	// Parsing arguments
	command_line_arguments_t cl_arguments = {};
	assert(argc > 1);
	int32_t arg_cursor = 1;
	while (arg_cursor < argc)
	{
		if (strcmp("--input", argv[arg_cursor]) == 0)
		{
			cl_arguments.input_path = argv[++arg_cursor];
			arg_cursor++;
			continue;
		}

		if (strcmp("--output", argv[arg_cursor]) == 0)
		{
			cl_arguments.output_path = argv[++arg_cursor];
			arg_cursor++;
			continue;
		}

		if (strcmp("--meshlets", argv[arg_cursor]) == 0)
		{
			cl_arguments.generate_meshlets = true;
			arg_cursor++;
			continue;
		}

		if (strcmp("--mikkt", argv[arg_cursor]) == 0)
		{
			cl_arguments.mikkt_space_tangents = true;
			arg_cursor++;
			continue;
		}

		if (strcmp("--interleaved", argv[arg_cursor]) == 0)
		{
			cl_arguments.interleaved = true;
			arg_cursor++;
			continue;
		}
	}

	assert(arg_cursor == argc);
	if (!cl_arguments.interleaved && !cl_arguments.generate_meshlets)
	{
		cl_arguments.interleaved = true;
	}

	printf("Input File: '%s'\n", cl_arguments.input_path);
	printf("Output File: '%s'\n", cl_arguments.output_path);
	printf("Generate Meshets: '%s'\n", cl_arguments.generate_meshlets ? "Yes" : "No");
	printf("Mikkt Space Tangents: '%s'\n", cl_arguments.mikkt_space_tangents ? "Yes" : "No");

	cgltf_options options{};
	cgltf_data* gltf_data = nullptr;
	cgltf_result result = cgltf_parse_file(&options, cl_arguments.input_path, &gltf_data);
	assert(result == cgltf_result_success);
	result = cgltf_load_buffers(&options, gltf_data, cl_arguments.input_path);
	assert(result == cgltf_result_success);

	uint32_t mesh_count = 0;
	for (uint32_t i = 0; i < gltf_data->meshes_count; ++i)
	{
		mesh_count += (uint32_t)gltf_data->meshes[i].primitives_count;
	}

	fixed_array_t<mesh_data_t> mesh_datas;
	mesh_datas.init(mesh_count);
	fixed_array_t<uint32_t> mesh_indices;
	mesh_indices.init(mesh_count);

	uint32_t mesh_index = 0;
	uint32_t first_index = 0;
	uint32_t first_vertex = 0;

	uint32_t flags = 0;
	if (cl_arguments.interleaved)
	{
		flags |= mesh_data_flag_interleaved;
	}

	if (cl_arguments.generate_meshlets)
	{
		flags |= mesh_data_flag_meshlets;
	}

	for (uint32_t mi = 0; mi < gltf_data->meshes_count; ++mi)
	{
		const cgltf_mesh& mesh = gltf_data->meshes[mi];
		for (uint32_t pi = 0; pi < mesh.primitives_count; ++pi)
		{
			const cgltf_primitive& primitive = mesh.primitives[pi];
			mesh_data_t& mesh_data = mesh_datas.data[mesh_index++];

			mesh_data.first_index = first_index;
			mesh_data.indices.init(primitive.indices->count);
			first_index += (uint32_t)primitive.indices->count;

			constexpr int index_map[] = { 0, 2, 1 };
			for (size_t i = 0; i < primitive.indices->count; i += 3)
			{
				mesh_data.indices.data[i + 0] = (uint32_t)cgltf_accessor_read_index(primitive.indices, i + index_map[0]);
				mesh_data.indices.data[i + 1] = (uint32_t)cgltf_accessor_read_index(primitive.indices, i + index_map[2]);
				mesh_data.indices.data[i + 2] = (uint32_t)cgltf_accessor_read_index(primitive.indices, i + index_map[1]);
			}

			for (size_t attr_index = 0; attr_index < primitive.attributes_count; ++attr_index)
			{
				const cgltf_attribute& attribute = primitive.attributes[attr_index];
				if (attribute.type == cgltf_attribute_type_position)
				{
					mesh_data.positions_stream.init(attribute.data->count);
					size_t unpacked_count = cgltf_accessor_unpack_floats(attribute.data, &mesh_data.positions_stream.data[0].x, attribute.data->count * 3);
					assert(unpacked_count > 0);
				}
				else if (attribute.type == cgltf_attribute_type_normal)
				{
					mesh_data.normals_stream.init(attribute.data->count);
					size_t unpacked_count = cgltf_accessor_unpack_floats(attribute.data, &mesh_data.normals_stream.data[0].x, attribute.data->count * 3);
					assert(unpacked_count > 0);
				}
				else if (attribute.type == cgltf_attribute_type_texcoord && attribute.index == 0) // TODO: Add support for multiple TEXCOORD
				{
					mesh_data.texcoords_stream.init(attribute.data->count);
					size_t unpacked_count = cgltf_accessor_unpack_floats(attribute.data, &mesh_data.texcoords_stream.data[0].x, attribute.data->count * 2);
					assert(unpacked_count > 0);
				}
			}

			if (cl_arguments.mikkt_space_tangents)
			{
				// TODO
			}

			// Optimizations
			meshopt_optimizeVertexCache(mesh_data.indices.data, mesh_data.indices.data, mesh_data.indices.count, mesh_data.positions_stream.count);
			meshopt_optimizeOverdraw(mesh_data.indices.data, mesh_data.indices.data, mesh_data.indices.count, &mesh_data.positions_stream.data[0].x, mesh_data.positions_stream.count, sizeof(float3_t), 1.05f);

			fixed_array_t<uint32_t> remap;
			remap.init(mesh_data.positions_stream.count);
			meshopt_optimizeVertexFetchRemap(&remap.data[0], mesh_data.indices.data, mesh_data.indices.count, mesh_data.positions_stream.count);
			meshopt_remapIndexBuffer(mesh_data.indices.data, mesh_data.indices.data, mesh_data.indices.count, &remap.data[0]);
			meshopt_remapVertexBuffer(mesh_data.positions_stream.data, mesh_data.positions_stream.data, mesh_data.positions_stream.count, sizeof(float3_t), &remap.data[0]);
			meshopt_remapVertexBuffer(mesh_data.normals_stream.data, mesh_data.normals_stream.data, mesh_data.normals_stream.count, sizeof(float3_t), &remap.data[0]);
			if (cl_arguments.mikkt_space_tangents)
			{
				meshopt_remapVertexBuffer(mesh_data.tangents_stream.data, mesh_data.tangents_stream.data, mesh_data.tangents_stream.count, sizeof(float3_t), &remap.data[0]);
			}
			meshopt_remapVertexBuffer(mesh_data.texcoords_stream.data, mesh_data.texcoords_stream.data, mesh_data.texcoords_stream.count, sizeof(float2_t), &remap.data[0]);
			remap.deinit();

			mesh_data.first_vertex = first_vertex;
			first_vertex += (uint32_t)mesh_data.positions_stream.count;

			if (cl_arguments.interleaved)
			{
				mesh_data.vertices.init(mesh_data.positions_stream.count);
				for (size_t i = 0; i < mesh_data.vertices.count; i++)
				{
					memcpy(&mesh_data.vertices.data[i].position, &mesh_data.positions_stream.data[i], sizeof(float3_t));
					memcpy(&mesh_data.vertices.data[i].normal, &mesh_data.normals_stream.data[i], sizeof(float3_t));
					memcpy(&mesh_data.vertices.data[i].texcoord0, &mesh_data.texcoords_stream.data[i], sizeof(float2_t));
					if (cl_arguments.mikkt_space_tangents)
					{
						memcpy(&mesh_data.vertices.data[i].tangent, &mesh_data.tangents_stream.data[i], sizeof(float4_t));
					}
					else
					{
						mesh_data.vertices.data[i].tangent.x = 1.0;
						mesh_data.vertices.data[i].tangent.x = 0.0;
						mesh_data.vertices.data[i].tangent.x = 0.0;
						mesh_data.vertices.data[i].tangent.x = 1.0;
					}
				}
			}

			if (cl_arguments.generate_meshlets)
			{
				// Meshlet generation
				const size_t max_vertices = 64;
				const size_t max_triangles = 124;
				const size_t max_meshlets = meshopt_buildMeshletsBound(mesh_data.indices.count, max_vertices, max_triangles);

				mesh_data.meshlets.init(max_meshlets);
				mesh_data.meshlet_vertices.init(max_meshlets * max_vertices);

				fixed_array_t<unsigned char> meshlet_triangles;
				meshlet_triangles.init(max_meshlets * max_triangles * 3);
				fixed_array_t<meshopt_Meshlet> meshlets;
				meshlets.init(max_meshlets);

				size_t meshlet_count = meshopt_buildMeshlets(meshlets.data, mesh_data.meshlet_vertices.data, meshlet_triangles.data,
					mesh_data.indices.data, mesh_data.indices.count, &mesh_data.positions_stream.data[0].x, mesh_data.positions_stream.count, sizeof(float3_t), max_vertices, max_triangles, 0);

				// Trimming
				meshopt_Meshlet& last = meshlets.data[meshlet_count - 1];
				meshlet_triangles.resize(last.triangle_offset + ((last.triangle_count * 3 + 3) & ~3));
				meshlets.resize(meshlet_count);

				mesh_data.meshlets.resize(meshlet_count);
				mesh_data.meshlet_vertices.resize(last.vertex_offset + last.vertex_count);
				mesh_data.meshlet_bounds.init(meshlet_count);
				mesh_data.meshlet_triangles.init(meshlet_triangles.count / 3);

				uint32_t triangle_offset = 0;
				for (size_t i = 0; i < meshlet_count; ++i)
				{
					const meshopt_Meshlet& meshlet = meshlets.data[i];
					float3_t min = { FLT_MAX, FLT_MAX, FLT_MAX };
					float3_t max = { -FLT_MAX, -FLT_MAX, -FLT_MAX };
					for (uint32_t k = 0; k < meshlet.triangle_count * 3; ++k)
					{
						uint32_t idx = mesh_data.meshlet_vertices.data[meshlet.vertex_offset + meshlet_triangles.data[meshlet.triangle_offset + k]];
						const float3_t p = mesh_data.positions_stream.data[idx];
						max = float3_max(max, p);
						min = float3_min(min, p);
					}
					meshlet_bounds_t& out_bounds = mesh_data.meshlet_bounds.data[i];
					out_bounds.local_center = (max + min) / 2;
					out_bounds.local_extents = (max - min) / 2;

					// Encode triangles and get rid of 4 bytes padding
					unsigned char* source_triangles = meshlet_triangles.data + meshlet.triangle_offset;
					meshopt_optimizeMeshlet(&mesh_data.meshlet_vertices.data[meshlet.vertex_offset], source_triangles, meshlet.triangle_count, meshlet.vertex_count);

					for (uint32_t tri_idx = 0; tri_idx < meshlet.triangle_count; ++tri_idx)
					{
						meshlet_triangle_t& tri = mesh_data.meshlet_triangles.data[tri_idx + triangle_offset];
						tri.v0 = *source_triangles++;
						tri.v1 = *source_triangles++;
						tri.v2 = *source_triangles++;
					}

					meshlet_t& out_meshlet = mesh_data.meshlets.data[i];
					out_meshlet.triangle_count = meshlet.triangle_count;
					out_meshlet.triangle_offset = triangle_offset;
					out_meshlet.vertex_count = meshlet.vertex_count;
					out_meshlet.vertex_offset = meshlet.vertex_offset;
					triangle_offset += meshlet.triangle_count;
				}

				mesh_data.meshlet_triangles.resize(triangle_offset);

				meshlets.deinit();
				meshlet_triangles.deinit();
			}
		}
	}

	// Write mesh data to file
	{
		FILE* file = nullptr;
		errno_t file_result = fopen_s(&file, cl_arguments.output_path, "wb");
		assert(file_result == 0);

		// Write magic
		fwrite(MESH_MAGIC, sizeof(MESH_MAGIC), 1, file);
		// Write flags
		fwrite((void*)&flags, sizeof(flags), 1, file);

		// Write mesh count
		fwrite((void*)&mesh_datas.count, sizeof(mesh_datas.count), 1, file);
		// Write meshes
		for (uint32_t i = 0; i < mesh_datas.count; ++i)
		{
			mesh_data_t& mesh_data = mesh_datas.data[i];

			// Write index count
			fwrite((void*)&mesh_data.indices.count, sizeof(mesh_data.indices.count), 1, file);

			if (cl_arguments.interleaved)
			{
				// Write first index
				fwrite((void*)&mesh_data.first_index, sizeof(mesh_data.first_index), 1, file);
				// Write vertex count
				fwrite((void*)&mesh_data.vertices.count, sizeof(mesh_data.vertices.count), 1, file);
				// Write first vertex
				fwrite((void*)&mesh_data.first_vertex, sizeof(mesh_data.first_vertex), 1, file);
			}
			else
			{
				// Write positions count
				fwrite((void*)&mesh_data.positions_stream.count, sizeof(mesh_data.positions_stream.count), 1, file);
				// Write texcoords count
				fwrite((void*)&mesh_data.texcoords_stream.count, sizeof(mesh_data.texcoords_stream.count), 1, file);
				// Write normals count
				fwrite((void*)&mesh_data.normals_stream.count, sizeof(mesh_data.normals_stream.count), 1, file);
				if (cl_arguments.mikkt_space_tangents)
				{
					// Write tangents count (optional)
					fwrite((void*)&mesh_data.tangents_stream.count, sizeof(mesh_data.tangents_stream.count), 1, file);
				}
				else
				{
					size_t tangents_count = 0;
					fwrite((void*)&tangents_count, sizeof(tangents_count), 1, file);
				}
			}
			
			if (cl_arguments.generate_meshlets)
			{
				// Write meshlets count (optional)
				fwrite((void*)&mesh_data.meshlets.count, sizeof(mesh_data.meshlets.count), 1, file);
				// Write meshlet_bounds count (optional)
				fwrite((void*)&mesh_data.meshlet_bounds.count, sizeof(mesh_data.meshlet_bounds.count), 1, file);
				// Write meshlet_triangles count (optional)
				fwrite((void*)&mesh_data.meshlet_triangles.count, sizeof(mesh_data.meshlet_triangles.count), 1, file);
				// Write meshlet_vertices count (optional)
				fwrite((void*)&mesh_data.meshlet_vertices.count, sizeof(mesh_data.meshlet_vertices.count), 1, file);
			}

			// Write data
			fwrite((void*)&mesh_data.indices.data[0], sizeof(mesh_data.indices.data[0]) * mesh_data.indices.count, 1, file);

			if (cl_arguments.interleaved)
			{
				fwrite((void*)&mesh_data.vertices.data[0], sizeof(mesh_data.vertices.data[0])* mesh_data.vertices.count, 1, file);
			}
			else
			{
				fwrite((void*)&mesh_data.positions_stream.data[0], sizeof(mesh_data.positions_stream.data[0])* mesh_data.positions_stream.count, 1, file);
				fwrite((void*)&mesh_data.texcoords_stream.data[0], sizeof(mesh_data.texcoords_stream.data[0])* mesh_data.texcoords_stream.count, 1, file);
				fwrite((void*)&mesh_data.normals_stream.data[0], sizeof(mesh_data.normals_stream.data[0])* mesh_data.normals_stream.count, 1, file);
				if (cl_arguments.mikkt_space_tangents && mesh_data.tangents_stream.count > 0)
				{
					fwrite((void*)&mesh_data.tangents_stream.data[0], sizeof(mesh_data.normals_stream.data[0]) * mesh_data.normals_stream.count, 1, file);
				}
			}

			if (cl_arguments.generate_meshlets)
			{
				fwrite((void*)&mesh_data.meshlets.data[0], sizeof(mesh_data.meshlets.data[0])* mesh_data.meshlets.count, 1, file);
				fwrite((void*)&mesh_data.meshlet_bounds.data[0], sizeof(mesh_data.meshlet_bounds.data[0])* mesh_data.meshlet_bounds.count, 1, file);
				fwrite((void*)&mesh_data.meshlet_triangles.data[0], sizeof(mesh_data.meshlet_triangles.data[0])* mesh_data.meshlet_triangles.count, 1, file);
				fwrite((void*)&mesh_data.meshlet_vertices.data[0], sizeof(mesh_data.meshlet_vertices.data[0])* mesh_data.meshlet_vertices.count, 1, file);
			}

		}
		fclose(file);
		file = nullptr;
	}

	// Read to test
	{
		FILE* file = nullptr;
		errno_t file_result = fopen_s(&file, cl_arguments.output_path, "rb");
		assert(file_result == 0);
		
		char magic[16];
		fread(&magic, sizeof(MESH_MAGIC), 1, file);
		
		uint32_t flags = 0;
		fread(&flags, sizeof(uint32_t), 1, file);
		if (cl_arguments.interleaved)
		{
			assert((flags & mesh_data_flag_interleaved) == mesh_data_flag_interleaved);
		}

		if (cl_arguments.generate_meshlets)
		{
			assert((flags & mesh_data_flag_meshlets) == mesh_data_flag_meshlets);
		}

		size_t mesh_count = 0;
		fread(&mesh_count, sizeof(mesh_count), 1, file);
		assert(mesh_count == mesh_datas.count);
		for (uint32_t i = 0; i < mesh_datas.count; ++i)
		{
			mesh_data_t& mesh_data = mesh_datas.data[i];
			size_t index_count = 0;
			fread(&index_count, sizeof(index_count), 1, file);
			assert(index_count == mesh_data.indices.count);

			if (cl_arguments.interleaved)
			{
				uint32_t first_index = 0;
				fread(&first_index, sizeof(first_index), 1, file);
				assert(first_index == mesh_data.first_index);

				size_t vertex_count = 0;
				fread(&vertex_count, sizeof(vertex_count), 1, file);
				assert(vertex_count == mesh_data.vertices.count);

				uint32_t first_vertex = 0;
				fread(&first_vertex, sizeof(first_vertex), 1, file);
				assert(first_vertex == mesh_data.first_vertex);
			}
			else
			{
				size_t positions_count = 0;
				fread(&positions_count, sizeof(positions_count), 1, file);
				assert(positions_count == mesh_data.positions_stream.count);
				size_t texcoords_count = 0;
				fread(&texcoords_count, sizeof(texcoords_count), 1, file);
				assert(texcoords_count == mesh_data.texcoords_stream.count);
				size_t normals_count = 0;
				fread(&normals_count, sizeof(normals_count), 1, file);
				assert(normals_count == mesh_data.normals_stream.count);

				size_t tangents_count = 0;
				if (cl_arguments.mikkt_space_tangents)
				{
					fread(&tangents_count, sizeof(tangents_count), 1, file);
					assert(tangents_count == mesh_data.tangents_stream.count);
				}
				else
				{
					fread(&tangents_count, sizeof(tangents_count), 1, file);
					assert(tangents_count == 0);
				}
			}

			if (cl_arguments.generate_meshlets)
			{
				size_t meshlets_count = 0;
				fread(&meshlets_count, sizeof(meshlets_count), 1, file);
				assert(meshlets_count == mesh_data.meshlets.count);

				size_t meshlet_bounds_count = 0;
				fread(&meshlet_bounds_count, sizeof(meshlet_bounds_count), 1, file);
				assert(meshlet_bounds_count == mesh_data.meshlet_bounds.count);

				size_t meshlet_triangles_count = 0;
				fread(&meshlet_triangles_count, sizeof(meshlet_triangles_count), 1, file);
				assert(meshlet_triangles_count == mesh_data.meshlet_triangles.count);

				size_t meshlet_vertices_count = 0;
				fread(&meshlet_vertices_count, sizeof(meshlet_vertices_count), 1, file);
				assert(meshlet_vertices_count == mesh_data.meshlet_vertices.count);
			}

			// Read data
			{
				size_t size = sizeof(uint32_t) * mesh_data.indices.count;
				uint32_t* indices = (uint32_t*)malloc(size);
				assert(indices);
				fread((void*)indices, size, 1, file);
				for (uint32_t ii = 0; ii < mesh_data.indices.count; ++ii)
				{
					assert(indices[ii] == mesh_data.indices.data[ii]);
				}
				free(indices);
				indices = nullptr;
			}

			if (cl_arguments.interleaved)
			{
				size_t size = sizeof(vertex_data_t) * mesh_data.vertices.count;
				vertex_data_t* vertices = (vertex_data_t*)malloc(size);
				assert(vertices);
				fread((void*)vertices, size, 1, file);
				for (uint32_t ii = 0; ii < mesh_data.vertices.count; ++ii)
				{
					assert(vertices[ii] == mesh_data.vertices.data[ii]);
				}
				free(vertices);
				vertices = nullptr;
			}
			else
			{
				{
					size_t size = sizeof(float3_t) * mesh_data.positions_stream.count;
					float3_t* positions = (float3_t*)malloc(size);
					assert(positions);
					fread((void*)positions, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.positions_stream.count; ++ii)
					{
						assert(positions[ii] == mesh_data.positions_stream.data[ii]);
					}
					free(positions);
					positions = nullptr;
				}

				{
					size_t size = sizeof(float3_t) * mesh_data.normals_stream.count;
					float3_t* normals = (float3_t*)malloc(size);
					assert(normals);
					fread((void*)normals, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.normals_stream.count; ++ii)
					{
						assert(normals[ii] == mesh_data.normals_stream.data[ii]);
					}
					free(normals);
					normals = nullptr;
				}
				
				{
					size_t size = sizeof(float2_t) * mesh_data.texcoords_stream.count;
					float2_t* texcoords = (float2_t*)malloc(size);
					assert(texcoords);
					fread((void*)texcoords, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.texcoords_stream.count; ++ii)
					{
						assert(texcoords[ii] == mesh_data.texcoords_stream.data[ii]);
					}
					free(texcoords);
					texcoords = nullptr;
				}

				if (cl_arguments.mikkt_space_tangents)
				{
					size_t size = sizeof(float3_t) * mesh_data.tangents_stream.count;
					float3_t* tangents = (float3_t*)malloc(size);
					assert(tangents);
					fread((void*)tangents, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.tangents_stream.count; ++ii)
					{
						assert(tangents[ii] == mesh_data.tangents_stream.data[ii]);
					}
					free(tangents);
					tangents = nullptr;
				}
			}

			if (cl_arguments.generate_meshlets)
			{
				{
					size_t size = sizeof(meshlet_t) * mesh_data.meshlets.count;
					meshlet_t* meshlets = (meshlet_t*)malloc(size);
					assert(meshlets);
					fread((void*)meshlets, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.meshlets.count; ++ii)
					{
						assert(meshlets[ii] == mesh_data.meshlets.data[ii]);
					}
					free(meshlets);
					meshlets = nullptr;
				}
				{
					size_t size = sizeof(meshlet_bounds_t) * mesh_data.meshlet_bounds.count;
					meshlet_bounds_t* meshlet_bounds = (meshlet_bounds_t*)malloc(size);
					assert(meshlet_bounds);
					fread((void*)meshlet_bounds, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.meshlet_bounds.count; ++ii)
					{
						assert(meshlet_bounds[ii] == mesh_data.meshlet_bounds.data[ii]);
					}
					free(meshlet_bounds);
					meshlet_bounds = nullptr;
				}
				{
					size_t size = sizeof(meshlet_triangle_t) * mesh_data.meshlet_triangles.count;
					meshlet_triangle_t* meshlet_triangles = (meshlet_triangle_t*)malloc(size);
					assert(meshlet_triangles);
					fread((void*)meshlet_triangles, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.meshlet_triangles.count; ++ii)
					{
						assert(meshlet_triangles[ii] == mesh_data.meshlet_triangles.data[ii]);
					}
					free(meshlet_triangles);
					meshlet_triangles = nullptr;
				}
				{
					size_t size = sizeof(uint32_t) * mesh_data.meshlet_vertices.count;
					uint32_t* meshlet_vertices = (uint32_t*)malloc(size);
					assert(meshlet_vertices);
					fread((void*)meshlet_vertices, size, 1, file);
					for (uint32_t ii = 0; ii < mesh_data.meshlet_vertices.count; ++ii)
					{
						assert(meshlet_vertices[ii] == mesh_data.meshlet_vertices.data[ii]);
					}
					free(meshlet_vertices);
					meshlet_vertices = nullptr;
				}
			}
		}

		fclose(file);
		file = nullptr;
	}

	for (uint32_t i = 0; i < mesh_datas.count; ++i)
	{
		mesh_data_t& mesh_data = mesh_datas.data[i];
		mesh_data.indices.deinit();
		mesh_data.positions_stream.deinit();
		mesh_data.normals_stream.deinit();
		if (cl_arguments.mikkt_space_tangents)
		{
			mesh_data.tangents_stream.deinit();
		}

		if (cl_arguments.generate_meshlets)
		{
			mesh_data.texcoords_stream.deinit();
			mesh_data.meshlets.deinit();
			mesh_data.meshlet_bounds.deinit();
			mesh_data.meshlet_triangles.deinit();
			mesh_data.meshlet_vertices.deinit();
		}
	}

	mesh_datas.deinit();
	mesh_indices.deinit();
	cgltf_free(gltf_data);

	return 0;	
}