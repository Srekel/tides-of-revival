const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const gfx = @import("../gfx_wgpu.zig");
const zgpu = @import("zgpu");
const zm = @import("zmath");

const fd = @import("../flecs_data.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const input = @import("../input.zig");
const config = @import("../config.zig");

const SystemState = struct {
    allocator: std.mem.Allocator,
    flecs_world: *flecs.World,
    sys: flecs.EntityId,

    // gfx: *gfx.GfxState,
    gctx: *zgpu.GraphicsContext,
    query_camera: flecs.Query,
    query_transform: flecs.Query,

    frame_data: *input.FrameData,
    switch_pressed: bool = false,
    active_index: u32 = 1,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.GfxState, flecs_world: *flecs.World, frame_data: *input.FrameData) !*SystemState {
    const gctx = gfxstate.gctx;

    var query_builder = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder
        .with(fd.Camera)
        .with(fd.Transform);
    var query_camera = query_builder.buildQuery();

    var query_builder_transform = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_transform
        .with(fd.Transform)
        .withReadonly(fd.Position)
        .withReadonly(fd.EulerRotation)
        .withReadonly(fd.Scale)
        .withReadonly(fd.Dynamic);

    var query_builder_transform_parent_term = query_builder_transform.manualTerm();
    query_builder_transform_parent_term.id = flecs_world.componentId(fd.Transform);
    query_builder_transform_parent_term.inout = flecs.c.EcsIn;
    query_builder_transform_parent_term.oper = flecs.c.EcsOptional;
    query_builder_transform_parent_term.subj.set.mask = flecs.c.EcsParent | flecs.c.EcsCascade;
    var query_transform = query_builder_transform.buildQuery();

    var state = allocator.create(SystemState) catch unreachable;
    var sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = state });
    state.* = .{
        .allocator = allocator,
        .flecs_world = flecs_world,
        .sys = sys,
        .gctx = gctx,
        .query_camera = query_camera,
        .query_transform = query_transform,
        .frame_data = frame_data,
    };

    flecs_world.observer(ObserverCallback, .on_set, state);

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_camera.deinit();
    state.query_transform.deinit();
    state.allocator.destroy(state);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var state = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    updateCameraSwitch(state);
    updateTransformHierarchy(state);
    updateCameraMatrices(state);
}

fn updateTransformHierarchy(state: *SystemState) void {
    var entity_iter_transform = state.query_transform.iterator(struct {
        transform: *fd.Transform,
        pos: *const fd.Position,
        rot: *const fd.EulerRotation,
        scale: *const fd.Scale,
        dynamic: *const fd.Dynamic,
        parent_transform: ?*const fd.Transform,
    });

    while (entity_iter_transform.next()) |comps| {
        const z_scale_matrix = zm.scaling(comps.scale.x, comps.scale.y, comps.scale.z);
        const z_rot_matrix = zm.matFromRollPitchYaw(comps.rot.pitch, comps.rot.yaw, comps.rot.roll);
        const z_translate_matrix = zm.translation(comps.pos.x, comps.pos.y, comps.pos.z);
        const z_sr_matrix = zm.mul(z_scale_matrix, z_rot_matrix);
        const z_srt_matrix = zm.mul(z_sr_matrix, z_translate_matrix);

        if (comps.parent_transform) |parent_transform| {
            const z_parent_matrix = zm.loadMat43(parent_transform.matrix[0..]);
            const z_world_matrix = zm.mul(z_srt_matrix, z_parent_matrix);
            zm.storeMat43(&comps.transform.matrix, z_world_matrix);
        } else {
            zm.storeMat43(&comps.transform.matrix, z_srt_matrix);
        }
    }
}

fn updateCameraMatrices(state: *SystemState) void {
    const gctx = state.gctx;
    const fb_width = gctx.swapchain_descriptor.width;
    const fb_height = gctx.swapchain_descriptor.height;

    var entity_iter = state.query_camera.iterator(struct {
        camera: *fd.Camera,
        transform: *fd.Transform,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }

        const transform = zm.loadMat43(comps.transform.matrix[0..]);
        var forward = zm.util.matForward(transform);
        var pos = transform[3];

        const world_to_view = zm.lookToLh(
            pos,
            forward,
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

fn updateCameraSwitch(state: *SystemState) void {
    if (!state.frame_data.just_pressed(config.input_camera_switch)) {
        return;
    }

    state.active_index = 1 - state.active_index;

    var builder = flecs.QueryBuilder.init(state.flecs_world.*);
    _ = builder
        .with(fd.Input)
        .optional(fd.Camera);

    var filter = builder.buildFilter();
    defer filter.deinit();

    var entity_iter = filter.iterator(struct { input: *fd.Input, cam: ?*fd.Camera });
    while (entity_iter.next()) |comps| {
        var active = false;
        if (comps.input.index == state.active_index) {
            active = true;
        }

        comps.input.active = active;
        if (comps.cam) |cam| {
            cam.active = active;
        }
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
            .active = ci.active,
            .class = ci.class,
        });
        ent.set(fd.Forward{ .x = 0, .y = 0, .z = 1 });
    }
}
