const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const zwin32 = @import("zwin32");

const fd = @import("flecs_data.zig");
const gfx = @import("gfx_d3d12.zig");
const mesh_loader = @import("renderer/mesh_loader.zig");
const util = @import("util.zig");
const rt = @import("renderer/renderer_types.zig");
const IdLocal = @import("variant.zig").IdLocal;

const assert = std.debug.assert;
const d3d12 = zwin32.d3d12;
const zcgltf = zmesh.io.zcgltf;

const PrefabHashMap = std.AutoHashMap(IdLocal, ecsu.Entity);

pub const PrefabManager = struct {
    prefab_hash_map: PrefabHashMap,
    is_a: ecsu.Entity,

    pub fn init(world: *ecsu.World, allocator: std.mem.Allocator) PrefabManager {
        return PrefabManager{
            .prefab_hash_map = PrefabHashMap.init(allocator),
            .is_a = ecsu.Entity.init(world.world, ecs.IsA),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.prefab_hash_map.deinit();
    }

    pub fn loadPrefabFromGLTF(self: *@This(), path: [:0]const u8, world: *ecsu.World, gfxstate: *gfx.D3D12State, allocator: std.mem.Allocator, args: struct { lods_count: u32 = 1, is_dynamic: bool = false }) !ecsu.Entity {
        const path_id = IdLocal.init(path);
        var existing_prefab = self.prefab_hash_map.get(path_id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        const data = try zmesh.io.parseAndLoadFile(path);
        defer zmesh.io.freeData(data);

        assert(data.scenes_count == 1);
        const scene = &data.scenes.?[0];
        assert(scene.nodes_count == 1);

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        var prefab = self.parseNode(scene.nodes.?[0], null, world, gfxstate, arena, args.lods_count, args.is_dynamic);
        self.prefab_hash_map.put(path_id, prefab) catch unreachable;

        return prefab;
    }

    pub fn getPrefabByPath(self: *@This(), path: []const u8) ?ecsu.Entity {
        const path_id = IdLocal.init(path);
        var existing_prefab = self.prefab_hash_map.get(path_id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        return null;
    }

    pub fn instantiatePrefab(self: @This(), world: *ecsu.World, prefab: ecsu.Entity) ecsu.Entity {
        const entity = world.newEntity();
        entity.addPair(self.is_a, prefab);
        return entity;
    }

    fn parseNode(self: *@This(), node: *zcgltf.Node, parent_entity: ?ecsu.Entity, world: *ecsu.World, gfxstate: *gfx.D3D12State, arena: std.mem.Allocator, lods_count: u32, is_dynamic: bool) ecsu.Entity {
        var entity = world.newPrefab(node.name);

        // Set parent
        if (parent_entity) |parent| {
            entity.addPair(ecs.ChildOf, parent);
            entity.setOverride(fd.Forward{});
        }

        if (is_dynamic) {
            entity.setOverride(fd.Dynamic{});
        }

        // Set position, rotation and scale
        var position = fd.Position.init(0, 0, 0);
        var rotation = fd.Rotation{};
        var scale = fd.Scale.createScalar(1);

        if (node.has_rotation != 0) {
            rotation.elems().* = node.rotation;
        }

        if (node.has_translation != 0) {
            position.x = node.translation[0];
            position.y = node.translation[1];
            position.z = node.translation[2];
        }

        if (node.has_scale != 0) {
            scale.x = node.scale[0];
            scale.y = node.scale[1];
            scale.z = node.scale[2];
        }
        entity.setOverride(position);
        entity.setOverride(rotation);
        entity.setOverride(scale);

        // Set transform
        var transform = fd.Transform.initWithQuaternion(rotation.elems().*);
        transform.setPos(position.elems().*);
        entity.setOverride(transform);

        // Parse and assign mesh and materials
        if (node.mesh != null) {
            var static_mesh_component: fd.StaticMeshComponent = undefined;

            const mesh_name = util.fromCStringToStringSlice(node.mesh.?.name.?);
            if (gfxstate.findMeshByName(mesh_name)) |mesh_handle| {
                static_mesh_component.mesh_handle = mesh_handle;

                for (0..node.mesh.?.primitives_count) |primitive_index| {
                    const primitive = &node.mesh.?.primitives[primitive_index];
                    static_mesh_component.material_handles[primitive_index] = self.parsePrimitiveMaterial(primitive, gfxstate, arena);
                }
            } else {
                assert(node.mesh.?.primitives_count <= rt.sub_mesh_count_max);
                var indices = std.ArrayList(rt.IndexType).init(arena);
                var vertices = std.ArrayList(rt.Vertex).init(arena);
                defer indices.deinit();
                defer vertices.deinit();

                var mesh = rt.Mesh{
                    .vertex_buffer = undefined,
                    .index_buffer = undefined,
                    .sub_mesh_count = @intCast(node.mesh.?.primitives_count),
                    .sub_meshes = undefined,
                    .bounding_box = undefined,
                };

                for (0..node.mesh.?.primitives_count) |primitive_index| {
                    const primitive = &node.mesh.?.primitives[primitive_index];
                    mesh.sub_meshes[primitive_index] = mesh_loader.parseMeshPrimitive(primitive, &indices, &vertices, arena) catch unreachable;
                    static_mesh_component.material_handles[primitive_index] = self.parsePrimitiveMaterial(primitive, gfxstate, arena);

                    // Generate LODs
                    if (lods_count > 1) {
                        assert(lods_count <= rt.lod_count_max);
                        var all_lods_indices = std.ArrayList(rt.IndexType).init(arena);

                        for (1..lods_count) |lod_index| {
                            var sub_mesh = &mesh.sub_meshes[primitive_index];
                            sub_mesh.lod_count += 1;

                            const threshold: f32 = 1.0 - @as(f32, @floatFromInt(lod_index)) / @as(f32, @floatFromInt(rt.lod_count_max));
                            const target_index_count: usize = @as(usize, @intFromFloat(@as(f32, @floatFromInt(indices.items.len)) * threshold));
                            const target_error: f32 = 1e-2;

                            var lod_indices = std.ArrayList(rt.IndexType).init(arena);
                            lod_indices.resize(indices.items.len) catch unreachable;
                            var lod_error: f32 = 0.0;
                            var lod_indices_count = zmesh.opt.simplifySloppy(
                                rt.Vertex,
                                lod_indices.items,
                                indices.items,
                                indices.items.len,
                                vertices.items,
                                vertices.items.len,
                                target_index_count,
                                target_error,
                                &lod_error,
                            );
                            lod_indices.resize(lod_indices_count) catch unreachable;

                            sub_mesh.lods[lod_index] = .{
                                .index_offset = sub_mesh.lods[lod_index - 1].index_offset + sub_mesh.lods[lod_index - 1].index_count,
                                .index_count = @as(u32, @intCast(lod_indices_count)),
                                .vertex_offset = sub_mesh.lods[0].vertex_offset,
                                .vertex_count = sub_mesh.lods[0].vertex_count,
                            };

                            all_lods_indices.appendSlice(lod_indices.items) catch unreachable;
                        }

                        indices.appendSlice(all_lods_indices.items) catch unreachable;
                    }
                }

                // Update mesh bounding box (encapsulates all sub-meshes bounding boxes)
                var min = [3]f32{ std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32) };
                var max = [3]f32{ std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32) };

                for (0..mesh.sub_mesh_count) |i| {
                    min[0] = @min(min[0], mesh.sub_meshes[i].bounding_box.min[0]);
                    min[1] = @min(min[1], mesh.sub_meshes[i].bounding_box.min[1]);
                    min[2] = @min(min[2], mesh.sub_meshes[i].bounding_box.min[2]);

                    max[0] = @max(max[0], mesh.sub_meshes[i].bounding_box.max[0]);
                    max[1] = @max(max[1], mesh.sub_meshes[i].bounding_box.max[1]);
                    max[2] = @max(max[2], mesh.sub_meshes[i].bounding_box.max[2]);
                }

                mesh.bounding_box = .{
                    .min = min,
                    .max = max,
                };

                static_mesh_component.mesh_handle = gfxstate.uploadMeshData(mesh_name, mesh, vertices.items, indices.items) catch unreachable;
            }

            entity.setOverride(static_mesh_component);
        }

        for (0..node.children_count) |i| {
            _ = self.parseNode(node.children.?[i], entity, world, gfxstate, arena, lods_count, is_dynamic);
        }

        return entity;
    }

    fn parsePrimitiveMaterial(
        _: *@This(),
        primitive: *const zcgltf.Primitive,
        gfxstate: *gfx.D3D12State,
        arena: std.mem.Allocator,
    ) gfx.MaterialHandle {
        const material = &primitive.material.?.*;
        assert(material.has_pbr_metallic_roughness == 1);

        const material_name = util.fromCStringToStringSlice(material.name.?);

        if (gfxstate.findMaterialByName(material_name)) |material_handle| {
            return material_handle;
        } else {
            var pbr_material = fd.PBRMaterial.init();

            pbr_material.base_color = fd.ColorRGB.init(
                material.pbr_metallic_roughness.base_color_factor[0],
                material.pbr_metallic_roughness.base_color_factor[1],
                material.pbr_metallic_roughness.base_color_factor[2],
            );

            pbr_material.metallic = material.pbr_metallic_roughness.metallic_factor;
            pbr_material.roughness = material.pbr_metallic_roughness.roughness_factor;
            pbr_material.normal_intensity = 1.0;
            pbr_material.emissive_strength = 1.0;

            if (material.alpha_mode == .mask) {
                pbr_material.surface_type = .mask;
            } else {
                pbr_material.surface_type = .@"opaque";
            }

            if (material.pbr_metallic_roughness.base_color_texture.texture) |texture| {
                if (texture.image) |image| {
                    if (image.*.uri) |uri| {
                        const texture_path = util.fromCStringToStringSlice(uri);
                        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
                        pbr_material.albedo = gfxstate.scheduleLoadTexture(texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = texture_path_u16 }, arena) catch unreachable;
                    }
                }
            }

            if (material.pbr_metallic_roughness.metallic_roughness_texture.texture) |texture| {
                if (texture.image) |image| {
                    if (image.*.uri) |uri| {
                        const texture_path = util.fromCStringToStringSlice(uri);
                        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
                        pbr_material.arm = gfxstate.scheduleLoadTexture(texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = texture_path_u16 }, arena) catch unreachable;
                    }
                }
            }

            if (material.normal_texture.texture) |texture| {
                if (texture.image) |image| {
                    if (image.*.uri) |uri| {
                        const texture_path = util.fromCStringToStringSlice(uri);
                        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
                        pbr_material.normal = gfxstate.scheduleLoadTexture(texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = texture_path_u16 }, arena) catch unreachable;
                    }
                }
            }

            if (material.emissive_texture.texture) |texture| {
                if (texture.image) |image| {
                    if (image.*.uri) |uri| {
                        const texture_path = util.fromCStringToStringSlice(uri);
                        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
                        pbr_material.emissive = gfxstate.scheduleLoadTexture(texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = texture_path_u16 }, arena) catch unreachable;
                    }
                }
            }

            if (material.has_emissive_strength == 1) {
                pbr_material.emissive_strength = material.emissive_strength.emissive_strength;
            }

            return gfxstate.storeMaterial(material_name, pbr_material) catch unreachable;
        }
    }
};
