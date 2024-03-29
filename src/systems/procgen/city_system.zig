const std = @import("std");
const ecs = @import("zflecs");
const znoise = @import("znoise");
const zm = @import("zmath");
const zphy = @import("zphysics");

const math = @import("../../core/math.zig");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const fr = @import("../../config/flecs_relation.zig");
const config = @import("../../config/config.zig");
const util = @import("../../util.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const AssetManager = @import("../../core/asset_manager.zig").AssetManager;
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    physics_world: *zphy.PhysicsSystem,
    sys: ecs.entity_t,
    asset_mgr: *AssetManager = undefined,
    prefab_mgr: *PrefabManager,

    query_city: ecsu.Query,
    query_camp: ecsu.Query,
    query_caravan: ecsu.Query,
    query_combat: ecsu.Query,
    query_syncpos: ecsu.Query,
};

const CityEnt = struct {
    class: u32,
    ent: ecsu.Entity,
    x: f32,
    z: f32,
    nearest: [2]ecs.entity_t = .{ 0, 0 },
    fn dist(self: CityEnt, other: CityEnt) f32 {
        return std.math.hypot(f32, self.x - other.x, self.z - other.z);
    }
};

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    physics_world: *zphy.PhysicsSystem,
    asset_mgr: *AssetManager,
    prefab_mgr: *PrefabManager,
) !*SystemState {
    var query_builder_city = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_city
        .with(fd.CompCity)
        .with(fd.Position);
    const query_city = query_builder_city.buildQuery();

    var query_builder_camp = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_camp
        .with(fd.CompBanditCamp)
        .with(fd.Position);
    const query_camp = query_builder_camp.buildQuery();

    var query_builder_caravan = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_caravan
        .with(fd.CompCaravan)
        .with(fd.Position);
    const query_caravan = query_builder_caravan.buildQuery();

    var query_builder_combat = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_combat
        .with(fd.CompCombatant)
        .with(fd.Position);
    const query_combat = query_builder_combat.buildQuery();

    var query_builder_syncpos = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_syncpos
        .with(fd.Position)
        .with(fd.Transform);
    const query_syncpos = query_builder_syncpos.buildQuery();

    const system = allocator.create(SystemState) catch unreachable;
    const sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .physics_world = physics_world,
        .sys = sys,
        .asset_mgr = asset_mgr,
        .prefab_mgr = prefab_mgr,
        .query_city = query_city,
        .query_camp = query_camp,
        .query_caravan = query_caravan,
        .query_combat = query_combat,
        .query_syncpos = query_syncpos,
    };
    return system;
}
pub fn createEntities(system: *SystemState) void {
    const ecsu_world = system.ecsu_world;
    var city_ents = std.ArrayList(CityEnt).init(system.allocator);
    defer city_ents.deinit();

    var added_spawn = false;

    // Cities from cities.txt
    const cities_data = system.asset_mgr.loadAssetBlocking(IdLocal.init("content/systems/cities.txt"), .instant_blocking);

    // var props = std.ArrayList(Prop).initCapacity(ctx.allocator, props_data.len / 30) catch unreachable;
    var buf_reader = std.io.fixedBufferStream(cities_data);
    var in_stream = buf_reader.reader();
    var buf: [1024]u8 = undefined;
    const sphere_prefab = system.prefab_mgr.getPrefab(config.prefab.sphere_id);
    while (in_stream.readUntilDelimiterOrEof(&buf, '\n') catch unreachable) |line| {
        var comma_curr: usize = 0;
        var comma_next: usize = std.mem.indexOfScalar(u8, line, ","[0]).?;
        const name = line[comma_curr..comma_next];
        _ = name;

        comma_curr = comma_next + 1;
        comma_next = comma_curr + std.mem.indexOfScalar(u8, line[comma_curr..], ","[0]).?;
        const pos_x = std.fmt.parseFloat(f32, line[comma_curr..comma_next]) catch unreachable;

        comma_curr = comma_next + 1;
        comma_next = comma_curr + std.mem.indexOfScalar(u8, line[comma_curr..], ","[0]).?;
        const pos_y = std.fmt.parseFloat(f32, line[comma_curr..comma_next]) catch unreachable;

        comma_curr = comma_next + 1;
        comma_next = comma_curr + std.mem.indexOfScalar(u8, line[comma_curr..], ","[0]).?;
        const pos_z = std.fmt.parseFloat(f32, line[comma_curr..comma_next]) catch unreachable;

        comma_curr = comma_next + 1;
        const rot_y = std.fmt.parseFloat(f32, line[comma_curr..]) catch unreachable;
        _ = rot_y;

        if (sphere_prefab) |sphere| {
            var city_ent = system.prefab_mgr.instantiatePrefab(ecsu_world, sphere);
            city_ent.set(fd.Position.init(pos_x, pos_y, pos_z));
            // city_ent.set(fd.Scale.createScalar(10));
            city_ents.append(.{ .ent = city_ent, .class = 0, .x = pos_x, .z = pos_z }) catch unreachable;

            if (!added_spawn) {
                added_spawn = true;
                const spawn_pos = fd.Position.init(pos_x, pos_y + 1, pos_z);
                var spawn_ent = system.ecsu_world.newEntity();
                spawn_ent.set(spawn_pos);
                spawn_ent.set(fd.SpawnPoint{ .active = true, .id = IdLocal.id64("player") });
                spawn_ent.addPair(fr.Hometown, city_ent);
                // spawn_ent.set(fd.Scale.createScalar(city_params.center_scale));
            }
        }

        var light_ent = system.ecsu_world.newEntity();
        light_ent.set(fd.Transform.initFromPosition(.{ .x = pos_x, .y = pos_y + 5, .z = pos_z }));
        light_ent.set(fd.PointLightComponent{
            .color = .{ .r = 1, .g = 0.5, .b = 0.25 },
            .range = 20.0,
            .intensity = 2.0,
        });

        // var light_viz_ent = ecsu_world.newEntity();
        // light_viz_ent.set(fd.Position.init(city_pos.x, city_height + 2 + city_params.light_range * 0.1, city_pos.z));
        // light_viz_ent.set(fd.Scale.createScalar(1));

    }

    // Cities
    for (city_ents.items) |*city_ent1| {
        if (city_ent1.class != 0) {
            continue;
        }
        var best_dist1: f32 = 1000000; // nearest
        var best_dist2: f32 = 1000000; // second nearest
        var best_ent1: ?CityEnt = null;
        var best_ent2: ?CityEnt = null;
        for (city_ents.items) |city_ent2| {
            if (city_ent1.ent.id == city_ent2.ent.id) {
                continue;
            }

            if (city_ent2.class == 1) {
                continue;
            }

            const dist = city_ent1.dist(city_ent2);
            if (dist < best_dist2) {
                best_dist2 = dist;
                best_ent2 = city_ent2;
            }
            if (dist < best_dist1) {
                best_dist2 = best_dist1;
                best_ent2 = best_ent1;
                best_dist1 = dist;
                best_ent1 = city_ent2;
            }
        }

        city_ent1.nearest[0] = best_ent1.?.ent.id;
        city_ent1.nearest[1] = best_ent2.?.ent.id;
        city_ent1.ent.set(fd.CompCity{
            .spawn_cooldown = 80,
            .next_spawn_time = 5,
            .closest_cities = [_]ecs.entity_t{
                best_ent1.?.ent.id,
                best_ent2.?.ent.id,
            },
            .curr_target_city = 0,
        });
    }

    // Bandits
    // for (city_ents.items) |city_ent1| {
    //     if (city_ent1.class != 1) {
    //         continue;
    //     }
    //     var best_dist1: f32 = 1000000; // nearest
    //     var best_ent1: ?CityEnt = null;
    //     for (city_ents.items) |city_ent2| {
    //         if (city_ent1.ent.id == city_ent2.ent.id) {
    //             continue;
    //         }

    //         if (city_ent2.class == 1) {
    //             continue;
    //         }

    //         const dist = city_ent1.dist(city_ent2);
    //         if (dist < best_dist1) {
    //             best_dist1 = dist;
    //             best_ent1 = city_ent2;
    //         }
    //     }

    //     city_ent1.ent.set(fd.CompBanditCamp{
    //         .spawn_cooldown = 65,
    //         .next_spawn_time = 10,
    //         .closest_cities = [_]ecs.entity_t{
    //             best_ent1.?.ent.id,
    //             best_ent1.?.nearest[0],
    //         },
    //         // .curr_target_city = 0,
    //     });
    // }
}

pub fn destroy(system: *SystemState) void {
    system.query_city.deinit();
    system.query_camp.deinit();
    system.query_caravan.deinit();
    system.query_combat.deinit();
    system.query_syncpos.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    _ = system;

    // const environment_info = system.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    // const world_time = environment_info.world_time;
    // var rand1 = std.rand.DefaultPrng.init(@floatToInt(u64, world_time * 100));
    // var rand = rand1.random();

    // // CITY
    // var entity_iter_city = system.query_city.iterator(struct {
    //     city: *fd.CompCity,
    //     pos: *fd.Position,
    // });

    // while (entity_iter_city.next()) |comps| {
    //     var city = comps.city;
    //     const pos = comps.pos;

    //     if (city.next_spawn_time < world_time) {
    //         if (city.caravan_members_to_spawn == 0) {
    //             city.next_spawn_time += city.spawn_cooldown;
    //             city.caravan_members_to_spawn = rand.intRangeAtMostBiased(i32, 3, 10);
    //             const city_index = rand.intRangeAtMost(u32, 0, 1);
    //             const next_city = flecs.Entity.init(system.ecsu_world.world, city.closest_cities[city_index]);
    //             city.curr_target_city = next_city.id;
    //             continue;
    //         }

    //         city.caravan_members_to_spawn -= 1;
    //         city.next_spawn_time += 0.05 + rand.float(f32) * 0.5;

    //         const next_city = flecs.Entity.init(system.ecsu_world.world, city.curr_target_city);
    //         const next_city_pos = next_city.get(fd.Position).?.*.elemsConst().*;
    //         const distance = math.dist3_xz(next_city_pos, pos.elemsConst().*);

    //         var caravan_ent = system.ecsu_world.newEntity();
    //         caravan_ent.set(fd.Transform{});
    //         caravan_ent.set(pos.*);
    //         caravan_ent.set(fd.Rotation.init(0, 0, 0));
    //         caravan_ent.set(fd.Scale.create(1, 3, 1));
    //         caravan_ent.set(fd.Dynamic{});
    //         caravan_ent.set(fd.CompCaravan{
    //             .start_pos = pos.elemsConst().*,
    //             .end_pos = next_city_pos,
    //             .time_birth = world_time,
    //             .time_to_arrive = world_time + distance / 10,
    //             .destroy_on_arrival = true,
    //         });
    //         caravan_ent.set(fd.CompCombatant{ .faction = 1 });
    //         if (city.caravan_members_to_spawn == 2) {
    //             caravan_ent.set(fd.Light{ .radiance = .{ .r = 4, .g = 1, .b = 0 }, .range = 12 });
    //         }
    //     }
    // }

    // // CAMP
    // var entity_iter_camp = system.query_camp.iterator(struct {
    //     camp: *fd.CompBanditCamp,
    //     pos: *fd.Position,
    // });

    // while (entity_iter_camp.next()) |comps| {
    //     var camp = comps.camp;
    //     const pos = comps.pos;

    //     if (camp.next_spawn_time < world_time) {
    //         if (camp.caravan_members_to_spawn == 0) {
    //             camp.next_spawn_time += camp.spawn_cooldown;
    //             camp.caravan_members_to_spawn = rand.intRangeAtMostBiased(i32, 2, 5);
    //             // const campIndex = rand.intRangeAtMost(u32, 0, 1);
    //             // const next_city = flecs.Entity.init(system.ecsu_world.world, camp.closest_cities[campIndex]);
    //             // camp.curr_target_city = next_city.id;
    //             continue;
    //         }

    //         camp.caravan_members_to_spawn -= 1;
    //         camp.next_spawn_time += 0.1 + rand.float(f32) * 1;

    //         const next_city1 = flecs.Entity.init(system.ecsu_world.world, camp.closest_cities[0]);
    //         const next_city2 = flecs.Entity.init(system.ecsu_world.world, camp.closest_cities[1]);
    //         const z_next_city_pos1 = zm.loadArr3(next_city1.get(fd.Position).?.elemsConst().*);
    //         const z_next_city_pos2 = zm.loadArr3(next_city2.get(fd.Position).?.elemsConst().*);
    //         const z_target_pos = (z_next_city_pos1 + z_next_city_pos2) * zm.f32x4s(0.5);
    //         const target_pos = zm.vecToArr3(z_target_pos);
    //         const distance = math.dist3_xz(target_pos, pos.elemsConst().*);

    //         var caravan_ent = system.ecsu_world.newEntity();
    //         caravan_ent.set(fd.Transform.init(pos.x, pos.y, pos.z));
    //         caravan_ent.set(fd.Scale.create(1, 3, 1));
    //         caravan_ent.set(fd.Rotation.init(0, 0, 0));
    //         caravan_ent.set(fd.Dynamic{});
    //         caravan_ent.set(fd.CompCaravan{
    //             .start_pos = pos.elemsConst().*,
    //             .end_pos = target_pos,
    //             .time_birth = world_time,
    //             .time_to_arrive = world_time + distance / 5,
    //             .destroy_on_arrival = false,
    //         });
    //         caravan_ent.set(fd.CompCombatant{ .faction = 2 });
    //     }
    // }

    // // CARAVAN
    // var entity_iter_caravan = system.query_caravan.iterator(struct {
    //     caravan: *fd.CompCaravan,
    //     pos: *fd.Position,
    // });

    // while (entity_iter_caravan.next()) |comps| {
    //     var caravan = comps.caravan;
    //     var pos = comps.pos;

    //     if (caravan.time_to_arrive < world_time) {
    //         if (caravan.destroy_on_arrival) {
    //             system.ecsu_world.delete(entity_iter_caravan.entity().id);
    //         } else {
    //             // hack :)
    //             system.ecsu_world.remove(entity_iter_caravan.entity().id, fd.CompBanditCamp);
    //         }
    //         continue;
    //     }

    //     const percent_done = (world_time - caravan.time_birth) / (caravan.time_to_arrive - caravan.time_birth);
    //     var new_pos: [3]f32 = .{
    //         caravan.start_pos[0] + percent_done * (caravan.end_pos[0] - caravan.start_pos[0]),
    //         0,
    //         caravan.start_pos[2] + percent_done * (caravan.end_pos[2] - caravan.start_pos[2]),
    //     };

    //     new_pos[1] = util.heightAtXZ(new_pos[0], new_pos[2], config.noise_scale_xz, config.noise_scale_y, config.noise_offset_y, &system.noise);

    //     pos.elems().* = new_pos;
    // }

    // // COMBAT
    // var entity_iter_combat1 = system.query_combat.iterator(struct {
    //     combat: *fd.CompCombatant,
    //     pos: *fd.Position,
    // });

    // combat_loop: while (entity_iter_combat1.next()) |comps1| {
    //     const combat1 = comps1.combat;
    //     const pos1 = comps1.pos;

    //     var entity_iter_combat2 = system.query_combat.iterator(struct {
    //         combat: *fd.CompCombatant,
    //         pos: *fd.Position,
    //     });

    //     while (entity_iter_combat2.next()) |comps2| {
    //         const combat2 = comps2.combat;
    //         const pos2 = comps2.pos;
    //         if (combat1.faction == combat2.faction) {
    //             continue;
    //         }
    //         const dist = math.dist3_xz(pos1.elems().*, pos2.elems().*);
    //         if (dist > 10) {
    //             continue;
    //         }

    //         if (combat1.faction == 1) {
    //             system.ecsu_world.delete(entity_iter_combat1.entity().id);
    //             ecs.iter_fini(entity_iter_combat1.iter);
    //             break :combat_loop;
    //         }
    //     }
    // }

    // LIGHTS
    // var entity_iter_syncpos = system.query_syncpos.iterator(struct {
    //     position: *fd.Position,
    //     transform: *fd.Transform,
    // });
    // while (entity_iter_syncpos.next()) |comps| {
    //     const transform = comps.transform;
    //     const pos = transform.getPos();
    //     comps.position.x = pos[0];
    //     comps.position.y = pos[1] + 1.5;
    //     comps.position.z = pos[2];
    // }
}
