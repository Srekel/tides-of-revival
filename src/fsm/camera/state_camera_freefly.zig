const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const IdLocal = @import("../../core/core.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../core/blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config/config.zig");
const util = @import("../../util.zig");
const context = @import("../../core/context.zig");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
};

pub fn create(create_ctx: StateContext) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(StateContext) catch unreachable;
    update_ctx.* = StateContext.view(create_ctx);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = fsm_cam_freefly_look;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_CAM, fd.FSM_CAM_Freefly), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 6);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "fsm_cam_freefly_look",
            ecs.OnUpdate,
            &system_desc,
        );
    }
    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = fsm_cam_freefly_move;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut },
            .{ .id = ecs.id(fd.Transform), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_CAM, fd.FSM_CAM_Freefly), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 6);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "fsm_cam_freefly_move",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn fsm_cam_freefly_look(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const inputs = ecs.field(it, fd.Input, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    const transforms = ecs.field(it, fd.Transform, 2).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;

    const movement_yaw = ctx.input_frame_data.get(config.input.look_yaw).number;
    const movement_pitch = ctx.input_frame_data.get(config.input.look_pitch).number;
    for (inputs, cameras, transforms, rotations) |input_comp, cam, transform, *rot| {
        _ = transform; // autofix
        _ = input_comp; // autofix

        if (!cam.active) {
            continue;
        }
        // TODO fix pitch clamp
        const rot_pitch = zm.quatFromNormAxisAngle(zm.Vec{ 1, 0, 0, 0 }, movement_pitch * 0.0025);
        const rot_yaw = zm.quatFromNormAxisAngle(zm.Vec{ 0, 1, 0, 0 }, movement_yaw * 0.0025);
        const rot_in = rot.asZM();
        const rot_new = zm.qmul(
            zm.qmul(rot_pitch, rot_in),
            rot_yaw,
        );
        rot.fromZM(rot_new);
    }
}

// fn updateLook(rot: *fd.Rotation, input_frame_data: *const input.FrameData) void {
//     const movement_yaw = input_frame_data.get(config.input.look_yaw).number;
//     const movement_pitch = input_frame_data.get(config.input.look_pitch).number;

//     const rot_pitch = zm.quatFromNormAxisAngle(zm.Vec{ 1, 0, 0, 0 }, movement_pitch * 0.0025);
//     const rot_yaw = zm.quatFromNormAxisAngle(zm.Vec{ 0, 1, 0, 0 }, movement_yaw * 0.0025);
//     const rot_in = rot.asZM();
//     const rot_pitch_new = zm.qmul(rot_in, rot_pitch);

//     const rpy = zm.quatToRollPitchYaw(rot_pitch_new);
//     const rpy_constrained = .{
//         std.math.clamp(rpy[0], -0.9, 0.9),
//         rpy[1],
//         rpy[2],
//     };
//     const constrained_z = zm.quatFromRollPitchYaw(rpy_constrained[0], rpy_constrained[1], rpy_constrained[2]);
//     const rot_new = zm.qmul(
//         constrained_z,
//         rot_yaw,
//     );
//     // const rpy = zm.quatToRollPitchYaw(rot_new);
//     // const rpy_constrained = .{
//     //     std.math.clamp(rpy[0], -0.9, 0.9),
//     //     rpy[1],
//     //     rpy[2],
//     // };
//     // // const rot_new = zm.qmul(zm.loadArr3(rpy_constrained), rot_yaw);
//     // const constrained_z = zm.quatFromRollPitchYaw(rpy_constrained[0], rpy_constrained[1], rpy_constrained[2]);

//     rot.fromZM(rot_new);
// }

fn fsm_cam_freefly_move(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const cameras = ecs.field(it, fd.Camera, 1).?;
    const rotations = ecs.field(it, fd.Rotation, 3).?;
    const positions = ecs.field(it, fd.Position, 4).?;

    var speed_scalar: f32 = 50.0;
    if (ctx.input_frame_data.held(config.input.move_fast)) {
        speed_scalar *= 50;
    } else if (ctx.input_frame_data.held(config.input.move_slow)) {
        speed_scalar *= 0.1;
    }

    const movement = zm.f32x4s(speed_scalar * it.delta_time);
    for (cameras, positions, rotations) |cam, *pos, *rot| {
        const transform = zm.matFromQuat(rot.asZM());
        var forward = zm.util.getAxisZ(transform);
        var right = zm.normalize3(zm.cross3(zm.f32x4(0.0, 1.0, 0.0, 0.0), forward));
        var up = zm.normalize3(zm.cross3(forward, right));

        if (!cam.active) {
            continue;
        }
        right = movement * right;
        forward = movement * forward;
        up = movement * up;

        var cpos = zm.load(pos.elems()[0..], zm.Vec, 3);

        if (ctx.input_frame_data.held(config.input.move_forward)) {
            cpos += forward;
        } else if (ctx.input_frame_data.held(config.input.move_backward)) {
            cpos -= forward;
        }

        if (ctx.input_frame_data.held(config.input.move_right)) {
            cpos += right;
        } else if (ctx.input_frame_data.held(config.input.move_left)) {
            cpos -= right;
        }

        if (ctx.input_frame_data.held(config.input.move_up)) {
            cpos += up;
        } else if (ctx.input_frame_data.held(config.input.move_down)) {
            cpos -= up;
        }

        zm.store(pos.elems()[0..], cpos, 3);

        if (ctx.input_frame_data.just_pressed(config.input.interact)) {
            const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
            const pos_comp = ecs.get_mut(ctx.ecsu_world.world, player_ent, fd.Position).?;
            pos_comp.* = pos.*;
        }
    }
}
