const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const gfx = @import("../gfx_wgpu.zig");
const zgpu = @import("zgpu");
const glfw = @import("glfw");
const zm = @import("zmath");

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;

const SystemState = struct {
    allocator: std.mem.Allocator,
    world: *flecs.World,
    sys: flecs.EntityId,

    // gfx: *gfx.GfxState,
    gctx: *zgpu.GraphicsContext,
    query: flecs.Query,

    // Camera movement, TODO move to other system
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.GfxState, world: *flecs.World) !*SystemState {
    const gctx = gfxstate.gctx;

    var query_builder = flecs.QueryBuilder.init(world.*)
        .with(fd.Camera)
        .with(fd.Position)
        .with(fd.Forward);

    var query = query_builder.buildQuery();

    var state = allocator.create(SystemState) catch unreachable;
    var sys = world.newWrappedRunSystem(name.toCString(), .on_update, fd.ComponentData, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .world = world,
        .sys = sys,
        .gctx = gctx,
        .query = query,
    };

    world.observer(ObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query.deinit();
    state.allocator.destroy(state);
}

fn updateLook(cam: *fd.Camera) void {
    const cursor_new = cam.window.getCursorPos() catch unreachable;
    const cursor_old = cam.cursor_known;
    cam.cursor_known = cursor_new;
    const delta_x = @floatCast(f32, cursor_new.xpos - cursor_old.xpos);
    const delta_y = @floatCast(f32, cursor_new.ypos - cursor_old.ypos);

    if (cam.window.getMouseButton(.right) == .press) {
        cam.pitch += 0.0025 * delta_y;
        cam.yaw += 0.0025 * delta_x;
        cam.pitch = math.min(cam.pitch, 0.48 * math.pi);
        cam.pitch = math.max(cam.pitch, -0.48 * math.pi);
        cam.yaw = zm.modAngle(cam.yaw);
    }
}

fn updateMovement(cam: *fd.Camera, pos: *fd.Position, fwd: *fd.Forward, dt: zm.F32x4) void {
    const window = cam.window;
    var speed_scalar: f32 = 500.0;
    if (window.getKey(.left_shift) == .press) {
        speed_scalar *= 10;
    }
    const speed = zm.f32x4s(speed_scalar);
    const transform = zm.mul(zm.rotationX(cam.pitch), zm.rotationY(cam.yaw));
    var forward = zm.normalize3(zm.mul(zm.f32x4(0.0, 0.0, 1.0, 0.0), transform));

    zm.store(fwd.elems()[0..], forward, 3);

    const right = speed * dt * zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
    forward = speed * dt * forward;

    var cpos = zm.load(pos.elems()[0..], zm.Vec, 3);

    if (window.getKey(.w) == .press) {
        cpos += forward;
    } else if (window.getKey(.s) == .press) {
        cpos -= forward;
    }
    if (window.getKey(.d) == .press) {
        cpos += right;
    } else if (window.getKey(.a) == .press) {
        cpos -= right;
    }

    zm.store(pos.elems()[0..], cpos, 3);
}

fn update(iter: *flecs.Iterator(fd.ComponentData)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    const dt4 = zm.f32x4s(iter.iter.delta_time);

    const gctx = state.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;

    var entity_iter = state.query.iterator(struct {
        camera: *fd.Camera,
        pos: *fd.Position,
        fwd: *fd.Forward,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;

        updateLook(cam);
        updateMovement(cam, comps.pos, comps.fwd, dt4);

        const world_to_view = zm.lookToLh(
            zm.load(comps.pos.elemsConst().*[0..], zm.Vec, 3),
            zm.load(comps.fwd.elemsConst().*[0..], zm.Vec, 3),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );

        const view_to_clip =
            zm.perspectiveFovLh(
            0.25 * math.pi,
            @intToFloat(f32, fb_width) / @intToFloat(f32, fb_height),
            comps.camera.near,
            comps.camera.far,
        );

        zm.storeMat(cam.world_to_view[0..], world_to_view);
        zm.storeMat(cam.view_to_clip[0..], view_to_clip);
        zm.storeMat(cam.world_to_clip[0..], zm.mul(world_to_view, view_to_clip));
    }
}

const ObserverCallback = struct {
    comp: *const fd.CICamera,

    pub const name = "CICamera";
    pub const run = onSetCICamera;
};

fn onSetCICamera(it: *flecs.Iterator(ObserverCallback)) void {
    // var observer = @ptrCast(*flecs.c.ecs_observer_t, @alignCast(@alignOf(flecs.c.ecs_observer_t), it.iter.ctx));
    // var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), observer.*.ctx));
    while (it.next()) |_| {
        const ci_ptr = flecs.c.ecs_term_w_size(it.iter, @sizeOf(fd.CICamera), @intCast(i32, it.index)).?;
        var ci = @ptrCast(*fd.CICamera, @alignCast(@alignOf(fd.CICamera), ci_ptr));
        const ent = it.entity();
        ent.remove(fd.CICamera);
        ent.set(fd.Camera{
            .far = ci.far,
            .near = ci.near,
            .window = ci.window,
        });
        ent.set(fd.Forward{ .x = 0, .y = 0, .z = 0 });
    }
}
