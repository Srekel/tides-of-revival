const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const ztracy = @import("ztracy");
const zwin32 = @import("zwin32");

const fd = @import("config/flecs_data.zig");
const renderer = @import("renderer/renderer.zig");
const util = @import("util.zig");
const IdLocal = @import("core/core.zig").IdLocal;

const assert = std.debug.assert;

const PrefabHashMap = std.AutoHashMap(IdLocal, ecsu.Entity);
const MaterialHashmap = std.AutoHashMap(IdLocal, fd.UberShader);

pub const PrefabManager = struct {
    prefab_hash_map: PrefabHashMap,
    material_hash_map: MaterialHashmap,
    is_a: ecsu.Entity,
    rctx: *renderer.Renderer,
    allocator: std.mem.Allocator,

    pub fn init(rctx: *renderer.Renderer, world: ecsu.World, allocator: std.mem.Allocator) PrefabManager {
        return PrefabManager{
            .allocator = allocator,
            .prefab_hash_map = PrefabHashMap.init(allocator),
            .material_hash_map = MaterialHashmap.init(allocator),
            .is_a = ecsu.Entity.init(world.world, ecs.IsA),
            .rctx = rctx,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.prefab_hash_map.deinit();
        self.material_hash_map.deinit();
    }

    pub fn createHierarchicalStaticMeshPrefab(self: *@This(), path: [:0]const u8, id: IdLocal, vertex_layout_id: IdLocal, world: ecsu.World) ecsu.Entity {
        const existing_prefab = self.prefab_hash_map.get(id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        var entity = world.newPrefab(id.toCString());
        entity.set(fd.Forward{});

        // Set position, rotation and scale
        var position = fd.Position.init(0, 0, 0);
        var rotation = fd.Rotation{};
        var scale = fd.Scale.createScalar(1);
        entity.set(position);
        entity.set(rotation);
        entity.set(scale);

        // Set transform
        var transform = fd.Transform.initWithQuaternion(rotation.elems().*);
        transform.setPos(position.elems().*);
        transform.setScale(scale.elems().*);
        entity.set(transform);

        const hierarchical_static_mesh = self.loadHierarchicalMesh(path, vertex_layout_id);
        entity.set(hierarchical_static_mesh);

        self.prefab_hash_map.put(id, entity) catch unreachable;
        return entity;
    }

    pub fn loadPrefabFromBinary(self: *@This(), path: [:0]const u8, id: IdLocal, vertex_layout_id: IdLocal, world: ecsu.World) ecsu.Entity {
        const existing_prefab = self.prefab_hash_map.get(id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        const mesh_handle = self.rctx.loadMesh(path, vertex_layout_id) catch unreachable;
        var entity = world.newPrefab(id.toCString());
        entity.set(fd.Forward{});

        // Set position, rotation and scale
        var position = fd.Position.init(0, 0, 0);
        var rotation = fd.Rotation{};
        var scale = fd.Scale.createScalar(1);
        entity.set(position);
        entity.set(rotation);
        entity.set(scale);

        // Set transform
        var transform = fd.Transform.initWithQuaternion(rotation.elems().*);
        transform.setPos(position.elems().*);
        transform.setScale(scale.elems().*);
        entity.set(transform);

        var static_mesh_component: fd.StaticMesh = undefined;
        static_mesh_component.mesh_handle = mesh_handle;
        entity.set(static_mesh_component);

        self.prefab_hash_map.put(id, entity) catch unreachable;
        return entity;
    }

    pub fn instantiatePrefab(self: @This(), world: ecsu.World, prefab: ecsu.Entity) ecsu.Entity {
        const entity = world.newEntity();
        entity.addPair(self.is_a, prefab);
        return entity;
    }

    pub fn getPrefab(self: *@This(), id: IdLocal) ?ecsu.Entity {
        const existing_prefab = self.prefab_hash_map.get(id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        return null;
    }

    pub fn storeMaterial(self: *@This(), id: IdLocal, material: fd.UberShader) void {
        self.material_hash_map.put(id, material) catch unreachable;
    }

    pub fn getMaterial(self: *@This(), id: IdLocal) ?fd.UberShader {
        const trazy_zone = ztracy.ZoneNC(@src(), "Get Material", 0x00_ff_ff_00);
        defer trazy_zone.End();

        const existing_material = self.material_hash_map.get(id);
        if (existing_material) |material| {
            return material;
        }

        return null;
    }

    fn loadHierarchicalMesh(self: *@This(), path: [:0]const u8, vertex_layout_id: IdLocal) fd.LodGroup {
        var lod_group = fd.LodGroup{
            .lod_count = 0,
            .lods = undefined,
        };

        // Try to load LODs
        for (0..renderer.mesh_lod_max_count) |lod| {
            var content_lod_path_buffer: [256]u8 = undefined;
            const content_lod_path = std.fmt.bufPrintZ(
                content_lod_path_buffer[0..content_lod_path_buffer.len],
                "content/{s}_LOD{d}.bin",
                .{ path, lod },
            ) catch unreachable;

            _ = std.fs.cwd().statFile(content_lod_path) catch |err| switch (err) {
                else => continue,
            };

            var lod_path_buffer: [256]u8 = undefined;
            const lod_path = std.fmt.bufPrintZ(
                lod_path_buffer[0..lod_path_buffer.len],
                "{s}_LOD{d}.bin",
                .{ path, lod },
            ) catch unreachable;

            lod_group.lods[lod_group.lod_count].mesh_handle = self.rctx.loadMesh(lod_path, vertex_layout_id) catch unreachable;

            const mesh = self.rctx.getMesh(lod_group.lods[lod_group.lod_count].mesh_handle);
            const num_materials: usize = @intCast(mesh.geometry.*.bitfield_1.mDrawArgCount);
            lod_group.lods[lod_group.lod_count].materials = std.ArrayList(renderer.MaterialHandle).initCapacity(self.allocator, num_materials) catch unreachable;
            for (0..num_materials) |_| {
                lod_group.lods[lod_group.lod_count].materials.appendAssumeCapacity(renderer.MaterialHandle.nil);
            }

            lod_group.lod_count += 1;
        }

        // Load non-lodded mesh
        if (lod_group.lod_count == 0) {
            var lod_path_buffer: [256]u8 = undefined;
            const lod_path = std.fmt.bufPrintZ(
                lod_path_buffer[0..lod_path_buffer.len],
                "{s}.bin",
                .{path},
            ) catch unreachable;

            lod_group.lods[lod_group.lod_count].mesh_handle = self.rctx.loadMesh(lod_path, vertex_layout_id) catch unreachable;

            const mesh = self.rctx.getMesh(lod_group.lods[lod_group.lod_count].mesh_handle);
            const num_materials: usize = @intCast(mesh.geometry.*.bitfield_1.mDrawArgCount);
            lod_group.lods[lod_group.lod_count].materials = std.ArrayList(renderer.MaterialHandle).initCapacity(self.allocator, num_materials) catch unreachable;
            for (0..num_materials) |_| {
                lod_group.lods[lod_group.lod_count].materials.appendAssumeCapacity(renderer.MaterialHandle.nil);
            }

            lod_group.lod_count += 1;
        }

        return lod_group;
    }
};
