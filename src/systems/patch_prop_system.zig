const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const fr = @import("../config/flecs_relation.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const PrefabManager = @import("../prefab_manager.zig").PrefabManager;
const ztracy = @import("ztracy");
const config = @import("../config/config.zig");
const context = @import("../core/context.zig");

const WorldLoaderData = struct {
    ent: ecs.entity_t = 0,
    pos_old: ?[3]f32 = null,
};

const Patch = struct {
    loaded: bool = false,
    entities: std.ArrayList(ecs.entity_t),
    lod: u32 = 1, // todo
    lookup: world_patch_manager.PatchLookup,
};

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    arena_system_update: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    prefab_mgr: *PrefabManager,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_update: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    prefab_mgr: *PrefabManager,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    state: struct {
        cam_pos_old: ?[3]f32 = null,
        patches: std.ArrayList(Patch),
        loaders: [1]WorldLoaderData = .{.{}},
        requester_id: world_patch_manager.RequesterId,
        // comp_query_loader: ecsu.Query,
        medium_house_prefab: ecsu.Entity,
        tree_prefab: ecsu.Entity,
        cube_prefab: ecsu.Entity,
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const medium_house_prefab = create_ctx.prefab_mgr.getPrefab(config.prefab.medium_house_id).?;
    const tree_prefab = create_ctx.prefab_mgr.getPrefab(config.prefab.beech_tree_04_id).?;
    const cube_prefab = create_ctx.prefab_mgr.getPrefab(config.prefab.cube_id).?;

    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .requester_id = create_ctx.world_patch_mgr.registerRequester(IdLocal.init("props")),
        .patches = std.ArrayList(Patch).initCapacity(create_ctx.heap_allocator, 4 * 4 * 32 * 32) catch unreachable,
        .medium_house_prefab = medium_house_prefab,
        .tree_prefab = tree_prefab,
        .cube_prefab = cube_prefab,
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = patchPropUpdateLoaders;
        system_desc.ctx = update_ctx;
        system_desc.ctx_free = destroy;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.WorldLoader), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .In },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "patchPropUpdateLoaders",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = patchPropUpdatePatches;
        system_desc.ctx = update_ctx;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "patchPropUpdatePatches",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

pub fn destroy(ctx: ?*anyopaque) callconv(.C) void {
    const system: *SystemUpdateContext = @ptrCast(@alignCast(ctx));
    for (system.state.patches.items) |patch| {
        patch.entities.deinit();
    }

    system.state.patches.deinit();
}

fn patchPropUpdateLoaders(it: *ecs.iter_t) callconv(.C) void {
    const system: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const world_loaders = ecs.field(it, fd.WorldLoader, 0).?;
    const transforms = ecs.field(it, fd.Transform, 1).?;

    var arena_state = std.heap.ArenaAllocator.init(system.arena_system_update);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    for (world_loaders, transforms, it.entities()) |loader_comp, transform, ent| {
        if (!loader_comp.props) {
            continue;
        }

        var loader = blk: {
            for (&system.state.loaders) |*loader| {
                if (loader.ent == ent) {
                    break :blk loader;
                }
            }

            // HACK
            system.state.loaders[0].ent = ent;
            break :blk &system.state.loaders[0];

            // unreachable;
        };

        const pos_new = transform.getPos00();
        if (loader.pos_old) |pos_old| {
            if (tides_math.dist3_xz(pos_new, pos_old) < 32) {
                continue;
            }
        }

        const patch_type_id = system.world_patch_mgr.getPatchTypeId(IdLocal.init("props"));
        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 16 * 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 16 * 1024) catch unreachable;

        const lod = 1;
        const radius = 2 * 1024;
        if (loader.pos_old) |pos_old| {
            const area_old = world_patch_manager.RequestRectangle{
                .x = pos_old[0] - radius,
                .z = pos_old[2] - radius,
                .width = radius * 2,
                .height = radius * 2,
            };

            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_old, lod, &lookups_old);
        }

        const area_new = world_patch_manager.RequestRectangle{
            .x = pos_new[0] - radius,
            .z = pos_new[2] - radius,
            .width = radius * 2,
            .height = radius * 2,
        };

        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(patch_type_id, area_new, lod, &lookups_new);

        var i_old: u32 = 0;
        blk: while (i_old < lookups_old.items.len) {
            var i_new: u32 = 0;
            while (i_new < lookups_new.items.len) {
                if (lookups_old.items[i_old].eql(lookups_new.items[i_new])) {
                    _ = lookups_old.swapRemove(i_old);
                    _ = lookups_new.swapRemove(i_new);
                    continue :blk;
                }
                i_new += 1;
            }
            i_old += 1;
        }

        // HACK
        if (loader.pos_old != null) {
            system.world_patch_mgr.removeLoadRequestFromLookups(system.state.requester_id, lookups_old.items);

            for (lookups_old.items) |lookup| {
                for (system.state.patches.items, 0..) |*patch, i| {
                    if (patch.lookup.eql(lookup)) {
                        // TODO: Batch delete
                        for (patch.entities.items) |patch_ent| {
                            system.ecsu_world.delete(patch_ent);
                        }

                        patch.entities.deinit();
                        _ = system.state.patches.swapRemove(i);
                        break;
                    }
                }
            }
        }
        loader.pos_old = pos_new;

        system.world_patch_mgr.addLoadRequestFromLookups(system.state.requester_id, lookups_new.items, .medium);

        for (lookups_new.items) |lookup| {
            system.state.patches.appendAssumeCapacity(.{
                .lookup = lookup,
                .lod = 1,
                .entities = std.ArrayList(ecs.entity_t).init(system.heap_allocator),
            });
        }
    }
}

// hack
var added_spawn = false;

fn patchPropUpdatePatches(it: *ecs.iter_t) callconv(.C) void {
    const system: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    for (system.state.patches.items) |*patch| {
        if (patch.loaded) {
            continue;
        }

        const Prop = struct {
            id: IdLocal,
            pos: [3]f32,
            rot: f32,
        };

        const patch_info = system.world_patch_mgr.tryGetPatch(patch.lookup, []Prop);
        if (patch_info.status != .not_loaded) {
            patch.loaded = true;
            if (patch_info.status == .loaded_empty or patch_info.status == .nonexistent) {
                break;
            }
            const data = patch_info.data_opt.?;

            const tree_id = IdLocal.init("tree");
            const wall_id = IdLocal.init("wall");
            const house_id = IdLocal.init("house");
            const city_id = IdLocal.init("city");
            var rand1 = std.Random.DefaultPrng.init(data.len);
            var rand = rand1.random();
            for (data.*) |prop| {
                const prop_pos = fd.Position.init(prop.pos[0], prop.pos[1], prop.pos[2]);
                const prop_scale: f32 = 1.0 + rand.float(f32) * 0.2;
                const prop_rot = fd.Rotation.initFromEuler(0, prop.rot + std.math.pi * 0.5, 0);

                var prop_transform: fd.Transform = undefined;
                const z_prop_scale_matrix = zm.scaling(prop_scale, prop_scale, prop_scale);
                const z_prop_rot_matrix = zm.matFromQuat(prop_rot.asZM());
                const z_prop_translate_matrix = zm.translation(prop_pos.x, prop_pos.y, prop_pos.z);
                const z_prop_sr_matrix = zm.mul(z_prop_scale_matrix, z_prop_rot_matrix);
                const z_prop_srt_matrix = zm.mul(z_prop_sr_matrix, z_prop_translate_matrix);
                zm.storeMat43(prop_transform.matrix[0..], z_prop_srt_matrix);
                prop_transform.updateInverseMatrix();

                if (prop.id.hash == house_id.hash) {
                    var house_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, system.state.medium_house_prefab);
                    house_ent.set(prop_transform);
                    house_ent.set(prop_pos);
                    house_ent.set(prop_rot);
                    house_ent.set(fd.Scale.createScalar(prop_scale));
                    patch.entities.append(house_ent.id) catch unreachable;
                } else if (prop.id.hash == tree_id.hash) {
                    var fir_tree_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, system.state.tree_prefab);
                    fir_tree_ent.set(prop_transform);
                    fir_tree_ent.set(prop_pos);
                    fir_tree_ent.set(prop_rot);
                    fir_tree_ent.set(fd.Scale.createScalar(prop_scale));
                    patch.entities.append(fir_tree_ent.id) catch unreachable;
                } else if (prop.id.hash == wall_id.hash) {
                    var wall_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, system.state.cube_prefab);
                    wall_ent.set(prop_transform);
                    wall_ent.set(prop_pos);
                    wall_ent.set(prop_rot);
                    wall_ent.set(fd.Scale.createScalar(prop_scale));
                    patch.entities.append(wall_ent.id) catch unreachable;
                } else {
                    var prop_ent = system.ecsu_world.newEntity();
                    prop_ent.set(prop_transform);
                    if (prop.id.hash == city_id.hash) {
                        // var light_ent = system.ecsu_world.newEntity();
                        // light_ent.set(fd.Transform.initFromPosition(.{ .x = prop.pos[0], .y = prop.pos[1] + 2 + 10, .z = prop.pos[2] }));
                        // light_ent.set(fd.Light{ .radiance = .{ .r = 4, .g = 2, .b = 1 }, .range = 100 });

                        // // var light_viz_ent = system.ecsu_world.newEntity();
                        // // light_viz_ent.set(fd.Position.init(city_pos.x, city_height + 2 + city_params.light_range * 0.1, city_pos.z));
                        // // light_viz_ent.set(fd.Scale.createScalar(1));

                        // if (!added_spawn) {
                        //     added_spawn = true;
                        //     var spawn_pos = fd.Position.init(prop.pos[0], prop.pos[1], prop.pos[2]);
                        //     var spawn_ent = system.ecsu_world.newEntity();
                        //     spawn_ent.set(spawn_pos);
                        //     spawn_ent.set(fd.SpawnPoint{ .active = true, .id = IdLocal.id64("player") });
                        //     spawn_ent.addPair(fr.Hometown, prop_ent);
                        //     // spawn_ent.set(fd.Scale.createScalar(city_params.center_scale));
                        // }
                    }
                    patch.entities.append(prop_ent.id) catch unreachable;
                }
            }
        }
    }
}
