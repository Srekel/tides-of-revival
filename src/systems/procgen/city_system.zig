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

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    physics_world: zbt.World,
    sys: flecs.EntityId,
    gctx: *zgpu.GraphicsContext,
    noise: znoise.FnlGenerator,
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
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .sys = sys,
        .gctx = gctx,
        .noise = noise,
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

    return state;
}

pub fn destroy(state: *SystemState) void {
    // state.query.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    _ = state;
}
