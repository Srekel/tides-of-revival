const std = @import("std");
const prefab_manager = @import("../prefab_manager.zig");
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
        .id = ID("prefabs/characters/player/theforge/player.bin"),
        .is_dynamic = true,
    },
    .{
        .id = ID("prefabs/creatures/giant_ant/theforge/giant_ant.bin"),
        .is_dynamic = true,
    },
    .{
        .id = ID("prefabs/props/bow_arrow/theforge/bow.bin"),
        .is_dynamic = true,
    },
    .{
        .id = ID("prefabs/props/bow_arrow/theforge/arrow.bin"),
        .is_dynamic = true,
    },
    .{
        .id = ID("prefabs/buildings/medium_house/theforge/medium_house.bin"),
    },
    .{
        .id = ID("prefabs/environment/fir/theforge/fir.bin"),
    },
    .{
        .id = ID("prefabs/primitives/theforge/primitive_cube.bin"),
        .is_dynamic = true,
    },
    .{
        .id = ID("prefabs/primitives/theforge/primitive_sphere.bin"),
        .is_dynamic = true,
    },
    .{
        .id = ID("prefabs/primitives/theforge/primitive_cylinder.bin"),
        .is_dynamic = true,
    },
};

pub var player: ecsu.Entity = undefined;
pub var giant_ant: ecsu.Entity = undefined;
pub var bow: ecsu.Entity = undefined;

pub fn initPrefabs(prefab_mgr: *prefab_manager.PrefabManager, ecsu_world: ecsu.World) void {
    // TODO(gmodarelli): Add a function to destroy the prefab's GPU resources
    for (prefabs) |prefab| {
        _ = prefab_mgr.loadPrefabFromBinary(
            prefab.id.toCString(),
            ecsu_world,
            .{ .is_dynamic = prefab.is_dynamic },
        );
    }

    player = prefab_mgr.getPrefabByPath("prefabs/characters/player/theforge/player.bin").?;
    giant_ant = prefab_mgr.getPrefabByPath("prefabs/creatures/giant_ant/theforge/giant_ant.bin").?;
    bow = prefab_mgr.getPrefabByPath("prefabs/props/bow_arrow/theforge/bow.bin").?;
}
