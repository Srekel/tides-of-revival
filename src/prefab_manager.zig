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

    pub fn init(rctx: *renderer.Renderer, world: ecsu.World, allocator: std.mem.Allocator) PrefabManager {
        return PrefabManager{
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

    pub fn loadPrefabFromBinary(self: *@This(), path: [:0]const u8, id: IdLocal, vertex_layout_id: IdLocal, world: ecsu.World) ecsu.Entity {
        const existing_prefab = self.prefab_hash_map.get(id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        const mesh_handle = self.rctx.loadMesh(path, vertex_layout_id) catch unreachable;
        var entity = world.newPrefab(path);
        entity.setOverride(fd.Forward{});

        // Set position, rotation and scale
        var position = fd.Position.init(0, 0, 0);
        var rotation = fd.Rotation{};
        var scale = fd.Scale.createScalar(1);
        entity.setOverride(position);
        entity.setOverride(rotation);
        entity.setOverride(scale);

        // Set transform
        var transform = fd.Transform.initWithQuaternion(rotation.elems().*);
        transform.setPos(position.elems().*);
        transform.setScale(scale.elems().*);
        entity.setOverride(transform);

        var static_mesh_component: fd.StaticMesh = undefined;
        static_mesh_component.mesh_handle = mesh_handle;
        entity.setOverride(static_mesh_component);

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
};
