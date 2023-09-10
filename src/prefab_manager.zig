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

    pub fn loadPrefabFromGLTF(self: *@This(), path: [:0]const u8, world: *ecsu.World, gfxstate: *gfx.D3D12State, allocator: std.mem.Allocator) !ecsu.Entity {
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

        var prefab = world.newPrefab(path);
        prefab.setOverride(fd.Position.init(0, 0, 0));
        prefab.setOverride(fd.Rotation{});
        prefab.setOverride(fd.Scale.createScalar(1));
        prefab.setOverride(fd.Transform{});
        prefab.setOverride(fd.Forward{});
        prefab.setOverride(fd.Dynamic{});
        self.parseNode(scene.nodes.?[0], prefab, world, gfxstate, arena);

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

    fn parseNode(
        self: *@This(),
        node: *zcgltf.Node,
        parent_entity: ecsu.Entity,
        world: *ecsu.World,
        gfxstate: *gfx.D3D12State,
        arena: std.mem.Allocator,
    ) void {
        // Set parent
        var entity = world.newPrefab(node.name);
        entity.addPair(ecs.ChildOf, parent_entity);
        entity.setOverride(fd.Forward{});
        entity.setOverride(fd.Dynamic{});

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

        // Parse and assign mesh
        if (node.mesh != null) {
            var static_mesh_component: fd.StaticMeshComponent = undefined;

            // TODO(gmodarelli): Cycle through all primitives
            assert(node.mesh.?.primitives_count == 1);
            const primitive = &node.mesh.?.primitives[0];

            const mesh_name = util.fromCStringToStringSlice(node.mesh.?.name.?);

            if (gfxstate.findMeshByName(mesh_name)) |mesh_handle| {
                static_mesh_component.mesh_handle = mesh_handle;
            } else {
                var indices = std.ArrayList(rt.IndexType).init(arena);
                var vertices = std.ArrayList(rt.Vertex).init(arena);
                indices.deinit();
                vertices.deinit();

                var mesh = mesh_loader.parseMeshPrimitive(primitive, &indices, &vertices, arena) catch unreachable;
                static_mesh_component.mesh_handle = gfxstate.uploadMeshData(mesh_name, mesh, vertices.items, indices.items) catch unreachable;
            }

            if (primitive.material != null) {
                const material = &primitive.material.?.*;
                assert(material.has_pbr_metallic_roughness == 1);

                const material_name = util.fromCStringToStringSlice(material.name.?);

                if (gfxstate.findMaterialByName(material_name)) |material_handle| {
                    static_mesh_component.material_handle = material_handle;
                } else {
                    var pbr_material = fd.PBRMaterial.init();

                    const base_color_texture = material.pbr_metallic_roughness.base_color_texture.texture.?.image.?.*;
                    const base_color_texture_path = util.fromCStringToStringSlice(base_color_texture.uri.?);
                    pbr_material.albedo = gfxstate.scheduleLoadTexture(base_color_texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = @as([*:0]const u16, @ptrCast(&base_color_texture_path)) }, arena) catch unreachable;

                    const metallic_roughness_texture = material.pbr_metallic_roughness.metallic_roughness_texture.texture.?.image.?.*;
                    const metallic_roughness_texture_path = util.fromCStringToStringSlice(metallic_roughness_texture.uri.?);
                    pbr_material.arm = gfxstate.scheduleLoadTexture(metallic_roughness_texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = @as([*:0]const u16, @ptrCast(&metallic_roughness_texture_path)) }, arena) catch unreachable;

                    const normal_texture = material.normal_texture.texture.?.image.?.*;
                    const normal_texture_path = util.fromCStringToStringSlice(normal_texture.uri.?);
                    pbr_material.normal = gfxstate.scheduleLoadTexture(normal_texture_path, .{ .state = d3d12.RESOURCE_STATES.COMMON, .name = @as([*:0]const u16, @ptrCast(&normal_texture_path)) }, arena) catch unreachable;

                    pbr_material.base_color = fd.ColorRGB.init(
                        material.pbr_metallic_roughness.base_color_factor[0],
                        material.pbr_metallic_roughness.base_color_factor[1],
                        material.pbr_metallic_roughness.base_color_factor[2],
                    );

                    pbr_material.metallic = material.pbr_metallic_roughness.metallic_factor;
                    pbr_material.roughness = material.pbr_metallic_roughness.roughness_factor;

                    static_mesh_component.material_handle = gfxstate.storeMaterial(material_name, pbr_material) catch unreachable;
                }
            }

            entity.setOverride(static_mesh_component);
        }

        var i: u32 = 0;
        while (i < node.children_count) : (i += 1) {
            self.parseNode(node.children.?[i], entity, world, gfxstate, arena);
        }
    }
};
