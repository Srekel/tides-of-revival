const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");
const zm = @import("zmath");
const zmesh = @import("zmesh");
const zwin32 = @import("zwin32");

const fd = @import("config/flecs_data.zig");
const renderer = @import("renderer/tides_renderer.zig");
const util = @import("util.zig");
const IdLocal = @import("core/core.zig").IdLocal;

const assert = std.debug.assert;

const PrefabHashMap = std.AutoHashMap(IdLocal, ecsu.Entity);

pub const PrefabManager = struct {
    prefab_hash_map: PrefabHashMap,
    is_a: ecsu.Entity,

    pub fn init(world: ecsu.World, allocator: std.mem.Allocator) PrefabManager {
        return PrefabManager{
            .prefab_hash_map = PrefabHashMap.init(allocator),
            .is_a = ecsu.Entity.init(world.world, ecs.IsA),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.prefab_hash_map.deinit();
    }

    pub fn loadPrefabFromBinary(self: *@This(), path: [:0]const u8, world: ecsu.World) ecsu.Entity {
        const path_id = IdLocal.init(path);
        const existing_prefab = self.prefab_hash_map.get(path_id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        const mesh_handle = renderer.loadMesh(path);
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

        var static_mesh_component: fd.StaticMeshComponent = undefined;
        static_mesh_component.mesh_handle = mesh_handle;
        entity.setOverride(static_mesh_component);

        self.prefab_hash_map.put(path_id, entity) catch unreachable;
        return entity;
    }

    pub fn instantiatePrefab(self: @This(), world: ecsu.World, prefab: ecsu.Entity) ecsu.Entity {
        const entity = world.newEntity();
        entity.addPair(self.is_a, prefab);
        return entity;
    }

    pub fn getPrefabByPath(self: *@This(), path: []const u8) ?ecsu.Entity {
        const path_id = IdLocal.init(path);
        const existing_prefab = self.prefab_hash_map.get(path_id);
        if (existing_prefab) |prefab| {
            return prefab;
        }

        return null;
    }
};
