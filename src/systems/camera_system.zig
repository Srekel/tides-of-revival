const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zm = @import("zmath");
const zgui = @import("zgui");
const ztracy = @import("ztracy");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const ID = @import("../core/core.zig").ID;
const input = @import("../input.zig");
const config = @import("../config/config.zig");
const renderer = @import("../renderer/renderer.zig");
const context = @import("../core/context.zig");

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
};

const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    state: struct {
        switch_pressed: bool = false,
        active_index: u32 = 1,
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{};

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateCameraSwitch;
        system_desc.ctx = update_ctx;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateCameraSwitch",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        // TODO: This should probably be done after game update and before render update.
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateTransformHierarchy;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Position), .inout = .In },
            .{ .id = ecs.id(fd.Rotation), .inout = .In },
            .{ .id = ecs.id(fd.Scale), .inout = .In },
            .{ .id = ecs.id(fd.Dynamic), .inout = .In }, // TODO: Should be .None I think
            .{ .id = ecs.id(fd.Transform), .inout = .Out },
            .{ .id = ecs.id(fd.Forward), .inout = .Out, .oper = .Optional },
            .{
                .id = ecs.id(fd.Transform),
                .inout = .In,
                .oper = .Optional,
                .src = .{ .id = ecs.Up | ecs.Cascade },
            },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 7);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateTransformHierarchy",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateCameraMatrices;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Transform), .inout = .In },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateCameraMatrices",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateCameraFrustum;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Camera), .inout = .Out },
            .{ .id = ecs.id(fd.Transform), .inout = .Out },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateCameraFrustum",
            ecs.OnUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = updateGui;
        system_desc.ctx = update_ctx;
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "updateGui",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn updateTransformHierarchy(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    _ = ctx; // autofix
    const is_actual_frame = it.delta_time > 0.00001;
    _ = is_actual_frame; // autofix
    const dt4: zm.F32x4 = @splat(it.delta_time);
    _ = dt4; // autofix

    const positions = ecs.field(it, fd.Position, 0).?;
    const rotations = ecs.field(it, fd.Rotation, 1).?;
    const scales = ecs.field(it, fd.Scale, 2).?;
    // const dynamics = ecs.field(it, fd.Dynamic, 3);
    const transforms = ecs.field(it, fd.Transform, 4).?;
    const forwards_opt = ecs.field(it, fd.Forward, 5);
    const parent_transforms_opt = ecs.field(it, fd.Transform, 6);

    // TODO: Break into two or more loops for less iffing.

    for (positions, rotations, scales, transforms, 0..) |pos, rot, scale, *transform, i| {
        const z_scale_matrix = zm.scaling(scale.x, scale.y, scale.z);
        const z_rot_matrix = zm.matFromQuat(rot.asZM());
        const z_translate_matrix = zm.translation(pos.x, pos.y, pos.z);
        const z_sr_matrix = zm.mul(z_scale_matrix, z_rot_matrix);
        const z_srt_matrix = zm.mul(z_sr_matrix, z_translate_matrix);

        const z_world_matrix = blk: {
            if (parent_transforms_opt) |parent_transforms| {
                const parent_transform = parent_transforms[i];
                const z_parent_matrix = zm.loadMat43(parent_transform.matrix[0..]);
                const z_world_matrix = zm.mul(z_srt_matrix, z_parent_matrix);
                break :blk z_world_matrix;
            } else {
                break :blk z_srt_matrix;
            }
        };

        if (forwards_opt) |forwards| {
            const fwd = &forwards[i];
            const z_fwd = zm.util.getAxisZ(z_world_matrix);
            zm.storeArr3(fwd.*.elems(), z_fwd);
        }

        // if (is_actual_frame) {
        //     if (vel) |vel| {
        //         const pos_prev = zm.loadArr3(comps.transform.getPos00());
        //         const pos_curr = zm.util.getTranslationVec(z_world_matrix);
        //         zm.storeArr3(vel.elems(), (pos_curr - pos_prev) / dt4);
        //     }
        // }
        zm.storeMat43(&transform.matrix, z_world_matrix);
    }
}

fn updateCameraMatrices(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const transforms = ecs.field(it, fd.Transform, 0).?;
    const cameras = ecs.field(it, fd.Camera, 1).?;
    for (cameras, transforms) |*cam, transform| {
        if (!cam.active) {
            continue;
        }

        const z_transform = zm.loadMat43(transform.matrix[0..]);
        const z_forward = zm.util.getAxisZ(z_transform);
        const z_pos = zm.util.getTranslationVec(z_transform);

        const z_view = zm.lookToLh(
            z_pos,
            z_forward,
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );

        const z_projection =
            zm.perspectiveFovLh(
            cam.fov,
            @as(f32, @floatFromInt(ctx.renderer.window_width)) / @as(f32, @floatFromInt(ctx.renderer.window_height)),
            cam.far,
            cam.near,
        );

        zm.storeMat(cam.view[0..], z_view);
        zm.storeMat(cam.projection[0..], z_projection);
        zm.storeMat(cam.view_projection[0..], zm.mul(z_view, z_projection));
    }
}

fn updateCameraSwitch(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    if (ctx.input_frame_data.just_pressed(config.input.toggle_player_control)) {
        for (ctx.input_frame_data.map.layer_stack.items) |*layer| {
            if (layer.id.eql(ID("on_foot"))) {
                layer.active = !layer.active;
                var window = ctx.input_frame_data.window;
                const cursor_mode: zglfw.Cursor.Mode = if (layer.active) .disabled else .normal;
                window.setInputMode(.cursor, cursor_mode);
            }
        }
    }

    if (!ctx.input_frame_data.just_pressed(config.input.camera_switch)) {
        return;
    }

    ctx.state.active_index = 1 - ctx.state.active_index;

    const query = ecs.query_init(ctx.ecsu_world.world, &.{
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Input), .inout = .InOut },
            .{ .id = ecs.id(fd.Camera), .inout = .InOut, .oper = .Optional },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
    }) catch unreachable;

    var query_iter = ecs.query_iter(ctx.ecsu_world.world, query);
    while (ecs.query_next(&query_iter)) {
        const inputs = ecs.field(&query_iter, fd.Input, 0).?;
        const cameras_opt = ecs.field(&query_iter, fd.Camera, 1);
        for (inputs, 0..) |*input_comp, i| {
            var active = false;
            if (input_comp.index == ctx.state.active_index) {
                active = true;
            }

            input_comp.active = active;
            if (cameras_opt) |cameras| {
                var cam = &cameras[i];
                cam.active = active;
                if (active) {
                    var environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
                    environment_info.active_camera = .{ .world = ctx.ecsu_world.world, .id = query_iter.entities()[i] };
                }
            }
        }
    }
}

fn updateCameraFrustum(it: *ecs.iter_t) callconv(.C) void {
    const cameras = ecs.field(it, fd.Camera, 0).?;
    for (cameras) |*cam| {
        if (!cam.active) {
            continue;
        }

        // TODO(gmodarelli): Check if renderer is frozen
        cam.calculateFrustumPlanes();
    }
}

fn updateGui(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));
    if (zgui.begin("Camera", .{})) {
        const environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
        if (environment_info.active_camera) |ent| {
            const pos = ent.get(fd.Transform).?.getPos();

            const transform_z = zm.matFromQuat(ent.get(fd.Rotation).?.asZM());
            const forward = zm.util.getAxisZ(transform_z);

            zgui.text("Cam pos: {d:.1}, {d:.1}, {d:.1}", .{ pos[0], pos[1], pos[2] });
            zgui.text("Cam dir: {d:.2}, {d:.2}, {d:.2}", .{ forward[0], forward[1], forward[2] });
        }
        if (environment_info.player) |ent| {
            const pos = ent.get(fd.Transform).?.getPos();
            zgui.text("Ply pos: {d:.1}, {d:.1}, {d:.1}", .{ pos[0], pos[1], pos[2] });
        }
    }
    zgui.end();
}
