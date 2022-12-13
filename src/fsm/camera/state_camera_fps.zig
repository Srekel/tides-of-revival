const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");
const zbt = @import("zbullet");

fn updateLook(rot: *fd.EulerRotation, input_state: *const input.FrameData) void {
    const pitch = input_state.get(config.input_look_pitch);
    rot.pitch += 0.0025 * pitch.number;
    rot.pitch = math.min(rot.pitch, 0.48 * math.pi);
    rot.pitch = math.max(rot.pitch, -0.48 * math.pi);
}

fn updateInteract(pos: *fd.Position, fwd: *fd.Forward, physics_world: zbt.World, flecs_world: *flecs.World, input_state: *const input.FrameData) void {
    // TODO: No, interaction shouldn't be in camera.. :)
    if (input_state.just_pressed(config.input_interact)) {
        var ray_result: zbt.RayCastResult = undefined;
        const ray_origin = fd.Position.init(pos.x, pos.y + 20, pos.z);
        const ray_end = fd.Position.init(pos.x + fwd.x * 5, pos.y + fwd.y * 5, pos.z + fwd.z * 5);
        const hit = physics_world.rayTestClosest(
            ray_origin.elemsConst()[0..],
            ray_end.elemsConst()[0..],
            .{ .default = true }, // zbt.CBT_COLLISION_FILTER_DEFAULT,
            zbt.CollisionFilter.all,
            .{ .use_gjk_convex_test = true }, // zbt.CBT_RAYCAST_FLAG_USE_GJK_CONVEX_TEST,
            &ray_result,
        );

        if (hit) {
            const light_pos = fd.Position.init(
                ray_result.hit_point_world[0],
                ray_result.hit_point_world[1],
                ray_result.hit_point_world[2],
            );

            const light_ent = flecs_world.newEntity();
            // light_ent.set();
            light_ent.set(light_pos);
            light_ent.set(fd.EulerRotation{});
            light_ent.set(fd.Scale.create(0.05, 1, 0.05));
            light_ent.set(fd.Transform.initFromPosition(light_pos));
            light_ent.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("cylinder"),
                .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 0.0, .roughness = 0.8 },
            });
            light_ent.set(fd.Light{ .radiance = .{ .r = 14, .g = 2, .b = 1 }, .range = 10 });
        }
    }
}
pub const StateIdle = struct {
    dummy: u32,
};

const StateCameraFPS = struct {
    query: flecs.Query,
};

fn enter(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StateCameraFPS, ctx.state.self);
    _ = self;
}

fn exit(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StateCameraFPS, ctx.state.self);
    _ = self;
}

fn update(ctx: fsm.StateFuncContext) void {
    // const self = Util.cast(StateIdle, ctx.data.ptr);
    // _ = self;
    const self = Util.castBytes(StateCameraFPS, ctx.state.self);
    var entity_iter = self.query.iterator(struct {
        input: *fd.Input,
        camera: *fd.Camera,
        pos: *fd.Position,
        fwd: *fd.Forward,
        rot: *fd.EulerRotation,
    });

    // std.debug.print("cam.active {any}a\n", .{cam.active});
    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }

        if (cam.class != 1) {
            // HACK
            continue;
        }

        updateLook(comps.rot, ctx.frame_data);
        updateInteract(
            comps.pos,
            comps.fwd,
            ctx.physics_world,
            ctx.flecs_world,
            ctx.frame_data,
        );
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Camera)
        .with(fd.Position)
        .with(fd.Forward)
        .with(fd.EulerRotation);

    var query = query_builder.buildQuery();
    var self = ctx.allocator.create(StateCameraFPS) catch unreachable;
    self.query = query;

    return .{
        .name = IdLocal.init("fps_camera"),
        .self = std.mem.asBytes(self),
        .size = @sizeOf(StateIdle),
        .transitions = std.ArrayList(fsm.Transition).init(ctx.allocator),
        .enter = enter,
        .exit = exit,
        .update = update,
    };
}

pub fn destroy() void {}
