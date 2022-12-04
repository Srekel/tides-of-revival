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

fn updateLook(rot: *fd.EulerRotation, input_state: *const input.FrameData) void {
    const pitch = input_state.get(config.input_cursor_movement_y);
    rot.pitch += 0.0025 * pitch.number;
    rot.pitch = math.min(rot.pitch, 0.48 * math.pi);
    rot.pitch = math.max(rot.pitch, -0.48 * math.pi);
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
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Camera)
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
