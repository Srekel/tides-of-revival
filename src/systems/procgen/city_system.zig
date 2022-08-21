const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const gfx = @import("../../gfx_wgpu.zig");
const zgpu = @import("zgpu");
const znoise = @import("znoise");
const glfw = @import("glfw");
const zm = @import("zmath");
const zbt = @import("zbullet");

const fd = @import("../../flecs_data.zig");
const IdLocal = @import("../../variant.zig").IdLocal;

const CompCity = struct {
    nextSpawnTime: f32,
    spawnCooldown: f32,
    caravanMembersToSpawn: i32 = 0,
    closestCities: [2]flecs.EntityId,
    currTargetCity: flecs.EntityId,
};
const CompCaravan = struct {
    startPos: [3]f32,
    endPos: [3]f32,
    timeToArrive: f32,
    timeBirth: f32,
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
    query: flecs.Query,
    query_caravan: flecs.Query,
};

const CityEnt = struct {
    ent: flecs.Entity,
    x: f32,
    z: f32,
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

    var query_builder = flecs.QueryBuilder.init(flecs_world.*)
        .with(CompCity)
        .with(fd.Transform);

    var query = query_builder.buildQuery();

    var query_builder_caravan = flecs.QueryBuilder.init(flecs_world.*)
        .with(CompCaravan)
        .with(fd.Transform);

    var query_caravan = query_builder_caravan.buildQuery();

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .sys = sys,
        .gctx = gctx,
        .noise = noise,
        .query = query,
        .query_caravan = query_caravan,
    };

    var cityEnts = std.ArrayList(CityEnt).init(allocator);
    defer cityEnts.deinit();

    var x: f32 = -2;
    while (x < 3) : (x += 2) {
        var z: f32 = -2;
        while (z < 3) : (z += 2) {
            var cityPos = .{
                .x = (x + 1.6 * state.noise.noise2(x * 1000, z * 1000)) * fd.patch_width,
                .y = 0,
                .z = (z + 1.6 * state.noise.noise2(x * 1000, z * 1000)) * fd.patch_width,
            };
            const cityHeight = 100 * (0.5 + state.noise.noise2(cityPos.x * 10.0000, cityPos.z * 10.0000));
            if (cityHeight < 25) {
                continue;
            }
            var cityEnt = flecs_world.newEntity();
            cityEnt.set(fd.Transform.init(cityPos.x, cityHeight, cityPos.z));
            cityEnt.set(fd.Scale.createScalar(10));
            cityEnt.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("sphere"),
                .basecolor_roughness = .{ .r = 1, .g = 1, .b = 1, .roughness = 0.8 },
            });
            cityEnts.append(.{ .ent = cityEnt, .x = cityPos.x, .z = cityPos.z }) catch unreachable;

            const radius: f32 = 50 * (1 + state.noise.noise2(x * 1000, z * 1000));
            const circumference: f32 = radius * std.math.pi * 2;
            const wallPartCount: f32 = 100;
            const wallLength = circumference / wallPartCount;
            var angle: f32 = 0;
            while (angle < 360) : (angle += 360 / wallPartCount) {
                const angleRadians = std.math.degreesToRadians(f32, angle);
                const angleRadiansHalf = std.math.degreesToRadians(f32, angle - 180 / wallPartCount);
                var wallPos = .{
                    .x = cityPos.x + radius * @cos(angleRadians),
                    .y = 0,
                    .z = cityPos.z + radius * @sin(angleRadians),
                };
                var wallCenterPos = .{
                    .x = cityPos.x + radius * @cos(angleRadiansHalf),
                    .y = 0,
                    .z = cityPos.z + radius * @sin(angleRadiansHalf),
                };
                const wallY = 100 * (0.5 + state.noise.noise2(wallCenterPos.x * 10.0000, wallCenterPos.z * 10.0000));
                if (wallY < 10) {
                    continue;
                }
                const zPos = zm.translation(wallPos.x, wallY - 4, wallPos.z);
                const zRot = zm.rotationY(-angleRadians + std.math.pi * 0.5);
                // const scale = zm.scaling(angleRadians);
                const zMat = zm.mul(zRot, zPos);
                var transform: fd.Transform = undefined;
                zm.storeMat43(transform.matrix[0..], zMat);
                var wallEnt = flecs_world.newEntity();
                wallEnt.set(transform);
                wallEnt.set(fd.Scale.create(wallLength, 8, 2));
                wallEnt.set(fd.CIShapeMeshInstance{
                    .id = IdLocal.id64("cube"),
                    .basecolor_roughness = .{ .r = 0.2, .g = 0.2, .b = 0.2, .roughness = 0.8 },
                });
            }

            const houseCount = 50;
            angle = 0;
            while (angle < 360) : (angle += 360 / houseCount) {
                // while (houseCount > 0) : (houseCount -= 1) {
                const angleRadians = std.math.degreesToRadians(f32, angle);
                const houseRadius = (1 + state.noise.noise2(angle * 1000, cityHeight * 100)) * radius * 0.5;
                var housePos = .{
                    .x = cityPos.x + houseRadius * @cos(angleRadians),
                    .y = 0,
                    .z = cityPos.z + houseRadius * @sin(angleRadians),
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
        }
    }

    for (cityEnts.items) |cityEnt1| {
        var bestDist1: f32 = 1000000; // nearest
        var bestDist2: f32 = 1000000; // second nearest
        var bestEnt1: ?CityEnt = null;
        var bestEnt2: ?CityEnt = null;
        for (cityEnts.items) |cityEnt2| {
            if (cityEnt1.ent.id == cityEnt2.ent.id) {
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

        cityEnt1.ent.set(CompCity{
            .spawnCooldown = 20,
            .nextSpawnTime = 10,
            .closestCities = [_]flecs.EntityId{
                bestEnt1.?.ent.id,
                bestEnt2.?.ent.id,
            },
            .currTargetCity = 0,
        });
    }

    return state;
}

pub fn destroy(state: *SystemState) void {
    // state.query.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state;
    // const dt4 = zm.f32x4s(iter.iter.delta_time);

    // const gctx = state.gctx;
    // const fb_width = gctx.swapchain_descriptor.width;
    // const fb_height = gctx.swapchain_descriptor.height;

    const time = @floatCast(f32, state.gctx.stats.time);
    var entity_iter = state.query.iterator(struct {
        city: *CompCity,
        transform: *fd.Transform,
    });

    var rand = std.rand.DefaultPrng.init(@floatToInt(u64, time * 100)).random();
    while (entity_iter.next()) |comps| {
        var city = comps.city;
        const transform = comps.transform;

        if (city.nextSpawnTime < state.gctx.stats.time) {
            if (city.caravanMembersToSpawn == 0) {
                city.nextSpawnTime += city.spawnCooldown;
                city.caravanMembersToSpawn = rand.intRangeAtMostBiased(i32, 3, 10);
                const cityIndex = rand.intRangeAtMost(u32, 0, 1);
                const nextCity = flecs.Entity.init(state.flecs_world.world, city.closestCities[cityIndex]);
                city.currTargetCity = nextCity.id;
                continue;
            }

            city.caravanMembersToSpawn -= 1;
            city.nextSpawnTime += 0.1 + rand.float(f32) * 1;

            const nextCity = flecs.Entity.init(state.flecs_world.world, city.currTargetCity);
            const nextCityPos = nextCity.get(fd.Transform).?;

            var caravanEnt = state.flecs_world.newEntity();
            caravanEnt.set(comps.transform.*);
            caravanEnt.set(fd.Scale.create(1, 3, 1));
            caravanEnt.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("cylinder"),
                .basecolor_roughness = .{ .r = 0.2, .g = 0.2, .b = 1.0, .roughness = 0.2 },
            });
            caravanEnt.set(CompCaravan{
                .startPos = transform.getPos(),
                .endPos = nextCityPos.getPos(),
                .timeBirth = time,
                .timeToArrive = time + 150,
            });
        }
    }

    var entity_iter_caravan = state.query_caravan.iterator(struct {
        caravan: *CompCaravan,
        transform: *fd.Transform,
    });

    while (entity_iter_caravan.next()) |comps| {
        var caravan = comps.caravan;
        var transform = comps.transform;

        if (caravan.timeToArrive < time) {
            state.flecs_world.delete(entity_iter_caravan.entity().id);
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

        // if (city.nextSpawnTime < time) {
        //     city.nextSpawnTime += city.spawnCooldown;

        //     const nextCity = flecs.Entity.init(state.flecs_world.world, city.closestCities[0]);
        //     const nextCityPos = nextCity.get(fd.Transform).?;

        //     var caravanEnt = state.flecs_world.newEntity();
        //     caravanEnt.set(comps.transform.*);
        //     caravanEnt.set(fd.Scale.create(1, 30, 1));
        //     caravanEnt.set(fd.CIShapeMeshInstance{
        //         .id = IdLocal.id64("cylinder"),
        //         .basecolor_roughness = .{ .r = 0.2, .g = 0.2, .b = 1.0, .roughness = 0.2 },
        //     });
        //     caravanEnt.set(CompCaravan{
        //         .startPos = transform.getPos(),
        //         .endPos = nextCityPos.getPos(),
        //         .timeBirth = 0,
        //         .timeToArrive = 10,
        //     });
        // }
    }
}
