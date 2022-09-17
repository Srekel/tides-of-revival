const std = @import("std");
const flecs = @import("flecs");
const gfx = @import("../../gfx_wgpu.zig");
const zgpu = @import("zgpu");
const znoise = @import("znoise");
const glfw = @import("glfw");
const zm = @import("zmath");
const zbt = @import("zbullet");

const math = @import("../../core/math.zig");
const fd = @import("../../flecs_data.zig");
const IdLocal = @import("../../variant.zig").IdLocal;

const CompCity = struct {
    nextSpawnTime: f32,
    spawnCooldown: f32,
    caravanMembersToSpawn: i32 = 0,
    closestCities: [2]flecs.EntityId,
    currTargetCity: flecs.EntityId,
};
const CompBanditCamp = struct {
    nextSpawnTime: f32,
    spawnCooldown: f32,
    caravanMembersToSpawn: i32 = 0,
    closestCities: [2]flecs.EntityId,
    // currTargetCity: flecs.EntityId,
};
const CompCaravan = struct {
    startPos: [3]f32,
    endPos: [3]f32,
    timeToArrive: f32,
    timeBirth: f32,
    destroy_on_arrival: bool,
};

const CompCombatant = struct {
    faction: i32,
};

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    sys: flecs.EntityId,

    // gfx: *gfx.GfxState,
    // gfx_stats: *zgpu.FrameStats,
    gctx: *zgpu.GraphicsContext,
    noise: znoise.FnlGenerator,
    query_city: flecs.Query,
    query_camp: flecs.Query,
    query_caravan: flecs.Query,
    query_combat: flecs.Query,
};

const CityEnt = struct {
    class: u32,
    ent: flecs.Entity,
    x: f32,
    z: f32,
    nearest: [2]flecs.EntityId = .{ 0, 0 },
    fn dist(self: CityEnt, other: CityEnt) f32 {
        return std.math.hypot(f32, self.x - other.x, self.z - other.z);
    }
};

pub fn create(
    name: IdLocal,
    allocator: std.mem.Allocator,
    gfxstate: *gfx.GfxState,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    noise: znoise.FnlGenerator,
) !*SystemState {
    const gctx = gfxstate.gctx;

    var query_builder_city = flecs.QueryBuilder.init(flecs_world.*)
        .with(CompCity)
        .with(fd.Transform);
    var query_city = query_builder_city.buildQuery();

    var query_builder_camp = flecs.QueryBuilder.init(flecs_world.*)
        .with(CompBanditCamp)
        .with(fd.Transform);
    var query_camp = query_builder_camp.buildQuery();

    var query_builder_caravan = flecs.QueryBuilder.init(flecs_world.*)
        .with(CompCaravan)
        .with(fd.Transform);
    var query_caravan = query_builder_caravan.buildQuery();

    var query_builder_combat = flecs.QueryBuilder.init(flecs_world.*)
        .with(CompCombatant)
        .with(fd.Transform);
    var query_combat = query_builder_combat.buildQuery();

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .sys = sys,
        .gctx = gctx,
        .noise = noise,
        .query_city = query_city,
        .query_camp = query_camp,
        .query_caravan = query_caravan,
        .query_combat = query_combat,
    };

    var cityEnts = std.ArrayList(CityEnt).init(allocator);
    defer cityEnts.deinit();

    const time = @floatCast(f32, state.gctx.stats.time);
    var rand = std.rand.DefaultPrng.init(@floatToInt(u64, time * 100)).random();
    var x: f32 = -2;
    while (x <= 2) : (x += 1.5) {
        var z: f32 = -2;
        while (z <= 2) : (z += 1.5) {
            var city_pos = .{
                .x = (x + 1.6 * state.noise.noise2(x * 1000, z * 1000)) * fd.patch_width,
                .y = 0,
                .z = (z + 1.6 * state.noise.noise2(x * 1000, z * 1000)) * fd.patch_width,
            };
            const cityHeight = 100 * (0.5 + state.noise.noise2(city_pos.x * 10.0000, city_pos.z * 10.0000));
            if (cityHeight < 25) {
                continue;
            }

            const CityParams = struct {
                center_color: fd.ColorRGBRoughness,
                center_scale: f32,
                wall_color: fd.ColorRGBRoughness,
                wall_count: f32,
                wall_radius: f32,
                wall_scale: fd.Scale,
                wall_random_rot: f32,
                house_count: f32,
                light_radiance: fd.ColorRGB,
                light_range: f32,
            };

            const cityClass = rand.intRangeAtMost(u1, 0, 1);
            const cityParams = switch (cityClass) {
                0 => blk: {
                    // CITY
                    break :blk CityParams{
                        .center_color = .{ .r = 1, .g = 1, .b = 1, .roughness = 0.8 },
                        .center_scale = 2,
                        .wall_color = .{ .r = 0.2, .g = 0.2, .b = 0.2, .roughness = 0.8 },
                        .wall_count = 100,
                        .wall_radius = 50,
                        .wall_random_rot = 0.0,
                        .wall_scale = .{ .x = 0, .y = 8, .z = 2 },
                        .house_count = 50,
                        .light_radiance = .{ .r = 4, .g = 2, .b = 1 },
                        .light_range = 70,
                    };
                },
                1 => blk: {
                    // CAMP
                    break :blk CityParams{
                        .center_color = .{ .r = 1.0, .g = 1.0, .b = 0.2, .roughness = 0.0 },
                        .center_scale = 0.5,
                        .wall_color = .{ .r = 0.8, .g = 0.5, .b = 0.0, .roughness = 0.8 },
                        .wall_count = 20,
                        .wall_radius = 10,
                        .wall_random_rot = 0.1,
                        .wall_scale = .{ .x = 0.2, .y = 4, .z = 0.2 },
                        .house_count = 1,
                        .light_radiance = .{ .r = 5, .g = 1, .b = 0 },
                        .light_range = 5,
                    };
                },
            };
            var cityEnt = flecs_world.newEntity();
            cityEnt.set(fd.Transform.init(city_pos.x, cityHeight, city_pos.z));
            cityEnt.set(fd.Scale.createScalar(cityParams.center_scale));
            cityEnt.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("sphere"),
                .basecolor_roughness = cityParams.center_color,
            });
            cityEnts.append(.{ .ent = cityEnt, .class = cityClass, .x = city_pos.x, .z = city_pos.z }) catch unreachable;

            const radius: f32 = cityParams.wall_radius * (1 + state.noise.noise2(x * 1000, z * 1000));
            const circumference: f32 = radius * std.math.pi * 2;
            const wallPartCount = cityParams.wall_count;
            const wallLength = circumference / wallPartCount;
            var angle: f32 = 0;
            while (angle < 360) : (angle += 360 / wallPartCount) {
                const angleRadians = std.math.degreesToRadians(f32, angle);
                const angleRadiansHalf = std.math.degreesToRadians(f32, angle - 180 / wallPartCount);
                var wallPos = .{
                    .x = city_pos.x + radius * @cos(angleRadians),
                    .y = 0,
                    .z = city_pos.z + radius * @sin(angleRadians),
                };
                var wallCenterPos = .{
                    .x = city_pos.x + radius * @cos(angleRadiansHalf),
                    .y = 0,
                    .z = city_pos.z + radius * @sin(angleRadiansHalf),
                };
                const wallY = 100 * (0.5 + state.noise.noise2(wallCenterPos.x * 10.0000, wallCenterPos.z * 10.0000));
                if (wallY < 5) {
                    continue;
                }
                const zPos = zm.translation(wallPos.x, wallY - cityParams.wall_scale.y * 0.5, wallPos.z);

                // TODO: A proper random angle, possibly with lookat
                const zRotY = zm.rotationY(-angleRadians + std.math.pi * 0.5);
                const zRotX = zm.rotationX((rand.float(f32) - 0.5) * cityParams.wall_random_rot);
                const zRotZ = zm.rotationX((rand.float(f32) - 0.5) * cityParams.wall_random_rot);
                const zMat = zm.mul(zm.mul(zRotY, zm.mul(zRotZ, zRotX)), zPos);
                var transform: fd.Transform = undefined;
                zm.storeMat43(transform.matrix[0..], zMat);
                var wallEnt = flecs_world.newEntity();
                wallEnt.set(transform);
                wallEnt.set(fd.Scale.create(if (cityParams.wall_scale.x == 0) wallLength else cityParams.wall_scale.x, cityParams.wall_scale.y, cityParams.wall_scale.z));
                wallEnt.set(fd.CIShapeMeshInstance{
                    .id = IdLocal.id64("cube"),
                    .basecolor_roughness = cityParams.wall_color,
                });
            }

            angle = 0;
            while (angle < 360) : (angle += 360 / cityParams.house_count) {
                // while (house_count > 0) : (house_count -= 1) {
                const angleRadians = std.math.degreesToRadians(f32, angle);
                const houseRadius = (1 + state.noise.noise2(angle * 1000, cityHeight * 100)) * radius * 0.5;
                var housePos = .{
                    .x = city_pos.x + houseRadius * @cos(angleRadians),
                    .y = 0,
                    .z = city_pos.z + houseRadius * @sin(angleRadians),
                };
                const houseY = 100 * (0.5 + state.noise.noise2(housePos.x * 10.0000, housePos.z * 10.0000));
                if (houseY < 10) {
                    continue;
                }
                var houseEnt = flecs_world.newEntity();
                const zPos = zm.translation(housePos.x, houseY - 2, housePos.z);
                const zRot = zm.rotationY(angleRadians);
                // const scale = zm.scaling(angleRadians);
                const zMat = zm.mul(zRot, zPos);
                var transform: fd.Transform = undefined;
                zm.storeMat43(transform.matrix[0..], zMat);
                houseEnt.set(transform);
                houseEnt.set(fd.Scale.create(7, 3, 4));
                houseEnt.set(fd.CIShapeMeshInstance{
                    .id = IdLocal.id64("cube"),
                    .basecolor_roughness = .{ .r = 1.0, .g = 0.2, .b = 0.2, .roughness = 0.8 },
                });
            }

            var lightEnt = state.flecs_world.newEntity();
            lightEnt.set(fd.Position{ .x = city_pos.x, .y = cityHeight + 1 + cityParams.light_range * 0.1, .z = city_pos.z });
            lightEnt.set(fd.Light{ .radiance = cityParams.light_radiance, .range = cityParams.light_range });
            // lightEnt.set(fd.Light{ .radiance = .{ 1, 1, 1 } });
        }
    }

    // Cities
    for (cityEnts.items) |*cityEnt1| {
        if (cityEnt1.class != 0) {
            continue;
        }
        var bestDist1: f32 = 1000000; // nearest
        var bestDist2: f32 = 1000000; // second nearest
        var bestEnt1: ?CityEnt = null;
        var bestEnt2: ?CityEnt = null;
        for (cityEnts.items) |cityEnt2| {
            if (cityEnt1.ent.id == cityEnt2.ent.id) {
                continue;
            }

            if (cityEnt2.class == 1) {
                continue;
            }

            const dist = cityEnt1.dist(cityEnt2);
            if (dist < bestDist2) {
                bestDist2 = dist;
                bestEnt2 = cityEnt2;
            }
            if (dist < bestDist1) {
                bestDist2 = bestDist1;
                bestEnt2 = bestEnt1;
                bestDist1 = dist;
                bestEnt1 = cityEnt2;
            }
        }

        cityEnt1.nearest[0] = bestEnt1.?.ent.id;
        cityEnt1.nearest[1] = bestEnt2.?.ent.id;
        cityEnt1.ent.set(CompCity{
            .spawnCooldown = 20,
            .nextSpawnTime = 5,
            .closestCities = [_]flecs.EntityId{
                bestEnt1.?.ent.id,
                bestEnt2.?.ent.id,
            },
            .currTargetCity = 0,
        });
    }

    // Bandits
    for (cityEnts.items) |cityEnt1| {
        if (cityEnt1.class != 1) {
            continue;
        }
        var bestDist1: f32 = 1000000; // nearest
        var bestEnt1: ?CityEnt = null;
        for (cityEnts.items) |cityEnt2| {
            if (cityEnt1.ent.id == cityEnt2.ent.id) {
                continue;
            }

            if (cityEnt2.class == 1) {
                continue;
            }

            const dist = cityEnt1.dist(cityEnt2);
            if (dist < bestDist1) {
                bestDist1 = dist;
                bestEnt1 = cityEnt2;
            }
        }

        cityEnt1.ent.set(CompBanditCamp{
            .spawnCooldown = 25,
            .nextSpawnTime = 10,
            .closestCities = [_]flecs.EntityId{
                bestEnt1.?.ent.id,
                bestEnt1.?.nearest[0],
            },
            // .currTargetCity = 0,
        });
    }

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_city.deinit();
    state.query_camp.deinit();
    state.query_caravan.deinit();
    state.query_combat.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state;

    const time = @floatCast(f32, state.gctx.stats.time);
    var rand = std.rand.DefaultPrng.init(@floatToInt(u64, time * 100)).random();

    // CITY
    var entity_iter_city = state.query_city.iterator(struct {
        city: *CompCity,
        transform: *fd.Transform,
    });

    while (entity_iter_city.next()) |comps| {
        var city = comps.city;
        const transform = comps.transform;

        if (city.nextSpawnTime < state.gctx.stats.time) {
            if (city.caravanMembersToSpawn == 0) {
                city.nextSpawnTime += city.spawnCooldown;
                city.caravanMembersToSpawn = rand.intRangeAtMostBiased(i32, 3, 10);
                const cityIndex = rand.intRangeAtMost(u32, 0, 1);
                const next_city = flecs.Entity.init(state.flecs_world.world, city.closestCities[cityIndex]);
                city.currTargetCity = next_city.id;
                continue;
            }

            city.caravanMembersToSpawn -= 1;
            city.nextSpawnTime += 0.1 + rand.float(f32) * 1;

            const next_city = flecs.Entity.init(state.flecs_world.world, city.currTargetCity);
            const next_city_pos = next_city.get(fd.Transform).?.getPos();
            const distance = math.dist3_xz(next_city_pos, transform.getPos());

            var caravanEnt = state.flecs_world.newEntity();
            caravanEnt.set(comps.transform.*);
            caravanEnt.set(fd.Scale.create(1, 3, 1));
            caravanEnt.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("cylinder"),
                .basecolor_roughness = .{ .r = 0.2, .g = 0.2, .b = 1.0, .roughness = 0.2 },
            });
            caravanEnt.set(CompCaravan{
                .startPos = transform.getPos(),
                .endPos = next_city_pos,
                .timeBirth = time,
                .timeToArrive = time + distance / 10,
                .destroy_on_arrival = true,
            });
            caravanEnt.set(CompCombatant{ .faction = 1 });
        }
    }

    // CAMP
    var entity_iter_camp = state.query_camp.iterator(struct {
        camp: *CompBanditCamp,
        transform: *fd.Transform,
    });

    while (entity_iter_camp.next()) |comps| {
        var camp = comps.camp;
        const transform = comps.transform;

        if (camp.nextSpawnTime < state.gctx.stats.time) {
            if (camp.caravanMembersToSpawn == 0) {
                camp.nextSpawnTime += camp.spawnCooldown;
                camp.caravanMembersToSpawn = rand.intRangeAtMostBiased(i32, 3, 10);
                // const campIndex = rand.intRangeAtMost(u32, 0, 1);
                // const next_city = flecs.Entity.init(state.flecs_world.world, camp.closestCities[campIndex]);
                // camp.currTargetCity = next_city.id;
                continue;
            }

            camp.caravanMembersToSpawn -= 1;
            camp.nextSpawnTime += 0.1 + rand.float(f32) * 1;

            const next_city1 = flecs.Entity.init(state.flecs_world.world, camp.closestCities[0]);
            const next_city2 = flecs.Entity.init(state.flecs_world.world, camp.closestCities[1]);
            const next_city_pos1_z = zm.loadArr3(next_city1.get(fd.Transform).?.*.getPos());
            const next_city_pos2_z = zm.loadArr3(next_city2.get(fd.Transform).?.*.getPos());
            const targetPos_z = (next_city_pos1_z + next_city_pos2_z) * zm.f32x4s(0.5);
            const targetPos = zm.vecToArr3(targetPos_z);
            const distance = math.dist3_xz(targetPos, transform.getPos());

            var caravanEnt = state.flecs_world.newEntity();
            caravanEnt.set(comps.transform.*);
            caravanEnt.set(fd.Scale.create(1, 3, 1));
            caravanEnt.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("cylinder"),
                .basecolor_roughness = .{ .r = 0.2, .g = 0.2, .b = 1.0, .roughness = 0.2 },
            });
            caravanEnt.set(CompCaravan{
                .startPos = transform.getPos(),
                .endPos = targetPos,
                .timeBirth = time,
                .timeToArrive = time + distance / 5,
                .destroy_on_arrival = false,
            });
            caravanEnt.set(CompCombatant{ .faction = 2 });
        }
    }

    // CARAVAN
    var entity_iter_caravan = state.query_caravan.iterator(struct {
        caravan: *CompCaravan,
        transform: *fd.Transform,
    });

    while (entity_iter_caravan.next()) |comps| {
        var caravan = comps.caravan;
        var transform = comps.transform;

        if (caravan.timeToArrive < time) {
            if (caravan.destroy_on_arrival) {
                state.flecs_world.delete(entity_iter_caravan.entity().id);
            } else {
                // hack :)
                state.flecs_world.remove(entity_iter_caravan.entity().id, CompBanditCamp);
            }
            continue;
        }

        const percentDone = (time - caravan.timeBirth) / (caravan.timeToArrive - caravan.timeBirth);
        var newPos: [3]f32 = .{
            caravan.startPos[0] + percentDone * (caravan.endPos[0] - caravan.startPos[0]),
            0,
            caravan.startPos[2] + percentDone * (caravan.endPos[2] - caravan.startPos[2]),
        };
        newPos[1] = 100 * (0.5 + state.noise.noise2(newPos[0] * 10.0000, newPos[2] * 10.0000));

        transform.setPos(newPos);
    }

    // COMBAT
    var entity_iter_combat1 = state.query_combat.iterator(struct {
        combat: *CompCombatant,
        transform: *fd.Transform,
    });
    while (entity_iter_combat1.next()) |comps1| {
        const combat1 = comps1.combat;
        const transform1 = comps1.transform;
        const pos1 = transform1.getPos();

        var entity_iter_combat2 = state.query_combat.iterator(struct {
            combat: *CompCombatant,
            transform: *fd.Transform,
        });

        while (entity_iter_combat2.next()) |comps2| {
            const combat2 = comps2.combat;
            const transform2 = comps2.transform;
            if (combat1.faction == combat2.faction) {
                continue;
            }
            const pos2 = transform2.getPos();
            const dist = math.dist3_xz(pos1, pos2);
            if (dist > 10) {
                continue;
            }

            if (combat1.faction == 1) {
                state.flecs_world.delete(entity_iter_combat1.entity().id);
                break;
            }
        }
    }
}
