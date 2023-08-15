const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");
const zphy = @import("zphysics");

fn updateLook(rot: *fd.Rotation, input_state: *const input.FrameData) void {
    const movement_pitch = input_state.get(config.input_look_pitch).number;
    const rot_pitch = zm.quatFromNormAxisAngle(zm.Vec{ 1, 0, 0, 0 }, movement_pitch * 0.0025);
    const rot_in = rot.asZM();
    const rot_new = zm.qmul(rot_in, rot_pitch);
    rot.fromZM(rot_new);
}

fn updateInteract(transform: *fd.Transform, physics_world: *zphy.PhysicsSystem, ecsu_world: ecsu.World, input_state: *const input.FrameData) void {
    // TODO: No, interaction shouldn't be in camera.. :)
    if (!input_state.just_pressed(config.input_interact)) {
        return;
    }

    const z_mat = zm.loadMat43(transform.matrix[0..]);
    const z_pos = zm.util.getTranslationVec(z_mat);
    const z_fwd = zm.util.getAxisZ(z_mat);

    const query = physics_world.getNarrowPhaseQuery();
    const ray_origin = [_]f32{ z_pos[0], z_pos[1], z_pos[2], 0 };
    const ray_dir = [_]f32{ z_fwd[0] * 50, z_fwd[1] * 50, z_fwd[2] * 50, 0 };
    var result = query.castRay(.{
        .origin = ray_origin,
        .direction = ray_dir,
    }, .{});

    if (result.has_hit) {
        const post_pos = fd.Position.init(
            ray_origin[0] + ray_dir[0] * result.hit.fraction,
            ray_origin[1] + ray_dir[1] * result.hit.fraction,
            ray_origin[2] + ray_dir[2] * result.hit.fraction,
        );
        var post_transform = fd.Transform.initFromPosition(post_pos);
        post_transform.setScale([_]f32{ 0.05, 2, 0.05 });

        const post_ent = ecsu_world.newEntity();
        post_ent.set(post_pos);
        post_ent.set(fd.Rotation{});
        post_ent.set(fd.Scale.create(0.05, 2, 0.05));
        post_ent.set(post_transform);
        post_ent.set(fd.CIShapeMeshInstance{
            .id = IdLocal.id64("cylinder"),
            .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 0.0, .roughness = 0.8 },
        });

        // const light_pos = fd.Position.init(0.0, 1.0, 0.0);
        // const light_transform = fd.Transform.init(post_pos.x, post_pos.y + 2.0, post_pos.z);
        // const light_ent = ecsu_world.newEntity();
        // light_ent.childOf(post_ent);
        // light_ent.set(light_pos);
        // light_ent.set(light_transform);
        // light_ent.set(fd.Light{ .radiance = .{ .r = 1, .g = 0.4, .b = 0.0 }, .range = 20 });
    }
}

pub const StateIdle = struct {
    dummy: u32,
};

const StateCameraFPS = struct {
    query: ecsu.Query,
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
        transform: *fd.Transform,
        // pos: *fd.Position,
        // fwd: *fd.Forward,
        rot: *fd.Rotation,
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
            comps.transform,
            // comps.fwd,
            ctx.physics_world,
            ctx.ecsu_world,
            ctx.frame_data,
        );
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = ecsu.QueryBuilder.init(ctx.ecsu_world);
    _ = query_builder
        .with(fd.Input)
        .with(fd.Camera)
        .with(fd.Transform)
    // .with(fd.Position)
    // .with(fd.Forward)
        .with(fd.Rotation);

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
