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

pub const SystemState = struct {
    flecs_sys: ecs.entity_t,
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    prefab_mgr: *PrefabManager,

    cam_pos_old: ?[3]f32 = null,
    patches: std.ArrayList(Patch),
    loaders: [1]WorldLoaderData = .{.{}},
    requester_id: world_patch_manager.RequesterId,
    comp_query_loader: ecsu.Query,
    medium_house_prefab: ecsu.Entity,
    fir_tree_prefab: ecsu.Entity,
    cube_prefab: ecsu.Entity,
};

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    prefab_mgr: *PrefabManager,
) !*SystemState {
    var query_builder_loader = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_loader.with(fd.WorldLoader)
        .with(fd.Transform);
    const comp_query_loader = query_builder_loader.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });

    const medium_house_prefab = prefab_mgr.getPrefabByPath("prefabs/buildings/medium_house/medium_house.bin").?;
    const fir_tree_prefab = prefab_mgr.getPrefabByPath("prefabs/environment/fir/fir.bin").?;
    const cube_prefab = prefab_mgr.getPrefabByPath("prefabs/primitives/primitive_cube.bin").?;

    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .world_patch_mgr = world_patch_mgr,
        .prefab_mgr = prefab_mgr,
        .comp_query_loader = comp_query_loader,
        .requester_id = world_patch_mgr.registerRequester(IdLocal.init("props")),
        .patches = std.ArrayList(Patch).initCapacity(allocator, 32 * 32) catch unreachable,
        .medium_house_prefab = medium_house_prefab,
        .fir_tree_prefab = fir_tree_prefab,
        .cube_prefab = cube_prefab,
    };

    // ecsu_world.observer(ObserverCallback, ecs.OnSet, system);

    // initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_loader.deinit();
    system.patches.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    updateLoaders(system);
    updatePatches(system);
}

fn updateLoaders(system: *SystemState) void {
    var entity_iter = system.comp_query_loader.iterator(struct {
        WorldLoader: *fd.WorldLoader,
        transform: *fd.Transform,
    });

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    while (entity_iter.next()) |comps| {
        var loader_comp = comps.WorldLoader;
        if (!loader_comp.props) {
            continue;
        }

        var loader = blk: {
            for (&system.loaders) |*loader| {
                if (loader.ent == entity_iter.entity()) {
                    break :blk loader;
                }
            }

            // HACK
            system.loaders[0].ent = entity_iter.entity();
            break :blk &system.loaders[0];

            // unreachable;
        };

        const pos_new = comps.transform.getPos00();
        if (loader.pos_old) |pos_old| {
            if (tides_math.dist3_xz(pos_new, pos_old) < 32) {
                continue;
            }
        }

        const patch_type_id = system.world_patch_mgr.getPatchTypeId(IdLocal.init("props"));
        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;

        const lod = 1;
        const radius = 1024;
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
            system.world_patch_mgr.removeLoadRequestFromLookups(system.requester_id, lookups_old.items);

            for (lookups_old.items) |lookup| {
                for (system.patches.items, 0..) |*patch, i| {
                    if (patch.lookup.eql(lookup)) {
                        // TODO: Batch delete
                        for (patch.entities.items) |ent| {
                            system.ecsu_world.delete(ent);
                        }

                        patch.entities.deinit();
                        _ = system.patches.swapRemove(i);
                        break;
                    }
                }
            }
        }
        loader.pos_old = pos_new;

        system.world_patch_mgr.addLoadRequestFromLookups(system.requester_id, lookups_new.items, .medium);

        for (lookups_new.items) |lookup| {
            system.patches.appendAssumeCapacity(.{
                .lookup = lookup,
                .lod = 1,
                .entities = std.ArrayList(ecs.entity_t).init(system.allocator),
            });
        }
    }
}

// hack
var added_spawn = false;

fn updatePatches(system: *SystemState) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Updating Patches", 0x00_ff_00_ff);
    defer trazy_zone.End();

    for (system.patches.items) |*patch| {
        if (patch.loaded) {
            continue;
        }

        const Prop = struct {
            id: IdLocal,
            pos: [3]f32,
            rot: f32,
        };

        const patch_info = system.world_patch_mgr.tryGetPatch(patch.lookup, Prop);
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
            var rand1 = std.rand.DefaultPrng.init(data.len);
            var rand = rand1.random();
            for (data) |prop| {
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

                if (prop.id.hash == house_id.hash) {
                    var house_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, system.medium_house_prefab);
                    house_ent.set(prop_transform);
                    house_ent.set(prop_pos);
                    house_ent.set(prop_rot);
                    house_ent.set(fd.Scale.createScalar(prop_scale));
                    patch.entities.append(house_ent.id) catch unreachable;
                } else if (prop.id.hash == tree_id.hash) {
                    var fir_tree_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, system.fir_tree_prefab);
                    fir_tree_ent.set(prop_transform);
                    fir_tree_ent.set(prop_pos);
                    fir_tree_ent.set(prop_rot);
                    fir_tree_ent.set(fd.Scale.createScalar(prop_scale));
                    patch.entities.append(fir_tree_ent.id) catch unreachable;
                } else if (prop.id.hash == wall_id.hash) {
                    var wall_ent = system.prefab_mgr.instantiatePrefab(system.ecsu_world, system.cube_prefab);
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
