const std = @import("std");
const pm = @import("../prefab_manager.zig");
const core = @import("../core/core.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const gfx = @import("../renderer/gfx_d3d12.zig");
const ID = core.ID;

const PrefabConfig = struct {
    id: core.IdLocal,
    is_dynamic: bool = false,
};
const prefabs = [_]PrefabConfig{
    .{
        .id = ID("content/prefabs/characters/player/player.gltf"),
        .is_dynamic = true,
    },
    .{
        .id = ID("content/prefabs/creatures/giant_ant/giant_ant.gltf"),
        .is_dynamic = true,
    },
    .{
        .id = ID("content/prefabs/props/bow_arrow/bow.gltf"),
        .is_dynamic = true,
    },
    .{
        .id = ID("content/prefabs/props/bow_arrow/arrow.gltf"),
        .is_dynamic = true,
    },
    .{
        .id = ID("content/prefabs/buildings/medium_house/medium_house.gltf"),
    },
    .{
        .id = ID("content/prefabs/environment/fir/fir.gltf"),
    },
    .{
        .id = ID("content/prefabs/primitives/primitive_cube.gltf"),
        .is_dynamic = true,
    },
    .{
        .id = ID("content/prefabs/primitives/primitive_sphere.gltf"),
        .is_dynamic = true,
    },
    .{
        .id = ID("content/prefabs/primitives/primitive_cylinder.gltf"),
        .is_dynamic = true,
    },
};

pub var player: ecsu.Entity = undefined;
pub var giant_ant: ecsu.Entity = undefined;
pub var bow: ecsu.Entity = undefined;

pub fn initPrefabs(prefab_manager: *pm.PrefabManager, ecsu_world: ecsu.World, allocator: std.mem.Allocator, gfx_state: *gfx.D3D12State) void {
    // TODO(gmodarelli): Add a function to destroy the prefab's GPU resources
    for (prefabs) |prefab| {
        _ = prefab_manager.loadPrefabFromGLTF(
            prefab.id.toCString(),
            ecsu_world,
            gfx_state,
            allocator,
            .{ .is_dynamic = prefab.is_dynamic },
        ) catch unreachable;
    }

    player = prefab_manager.getPrefabByPath("content/prefabs/characters/player/player.gltf").?;
    giant_ant = prefab_manager.getPrefabByPath("content/prefabs/creatures/giant_ant/giant_ant.gltf").?;
    bow = prefab_manager.getPrefabByPath("content/prefabs/props/bow_arrow/bow.gltf").?;
}
