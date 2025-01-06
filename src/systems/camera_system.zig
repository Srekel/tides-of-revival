const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zm = @import("zmath");
const zgui = @import("zgui");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const ID = @import("../core/core.zig").ID;
const input = @import("../input.zig");
const config = @import("../config/config.zig");
const renderer = @import("../renderer/renderer.zig");
const ztracy = @import("ztracy");

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    sys: ecs.entity_t,

    query_camera: ecsu.Query,
    query_transform: ecsu.Query,

    input_frame_data: *input.FrameData,
    switch_pressed: bool = false,
    active_index: u32 = 1,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, ecsu_world: ecsu.World, input_frame_data: *input.FrameData, rctx: *renderer.Renderer) !*SystemState {
    var query_builder = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder
        .with(fd.Camera)
        .with(fd.Transform);
    const query_camera = query_builder.buildQuery();

    var query_builder_transform = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_transform
        .with(fd.Transform)
        .optional(fd.Forward)
        .optional(fd.Velocity)
        .withReadonly(fd.Position)
        .withReadonly(fd.Rotation)
        .withReadonly(fd.Scale)
        .withReadonly(fd.Dynamic);

    var query_builder_transform_parent_term = query_builder_transform.manualTerm();
    query_builder_transform_parent_term.id = ecsu_world.componentId(fd.Transform);
    query_builder_transform_parent_term.inout = .In;
    query_builder_transform_parent_term.oper = .optional;
    query_builder_transform_parent_term.src.flags = ecs.Parent | ecs.Cascade;
    const query_transform = query_builder_transform.buildQuery();

    //     var edesc = ecs.system_desc_t{};
    //     edesc.id = 0;
    //     edesc.name = name.toCString();
    //     edesc.add[0] = ecs.pair(ecs.DependsOn, ecs.OnUpdate);
    //     edesc.add[1] = ecs.OnUpdate;

    //     // var system_desc =  ecs.system_desc_t{};
    //     // system_desc.entity = ecs.entity_init(ecsu_world, &edesc);
    //     // system_desc.query.filter = ecsu.meta.generateFilterDesc(self, Components);
    //     // system_desc.callback = dummyFn;
    //     // system_desc.run = wrapSystemFn(Components, action);
    //     // system_desc.ctx = params.ctx;
    //     // return ecs.system_init(self.world, &system_desc);
    // var sys = ecs.SYSTEM(ecsu_world, name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });

    const system = allocator.create(SystemState) catch unreachable;

    const sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .renderer = rctx,
        .query_camera = query_camera,
        .query_transform = query_transform,
        .input_frame_data = input_frame_data,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.query_camera.deinit();
    system.query_transform.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Camera System: Update", 0x00_ff_00_ff);
    defer trazy_zone.End();

    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    updateCameraSwitch(system);
    updateTransformHierarchy(system, iter.iter.delta_time);
    updateCameraMatrices(system);
    updateCameraFrustum(system);

    if (zgui.begin("Camera", .{})) {
        const environment_info = system.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
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

fn updateTransformHierarchy(system: *SystemState, dt: f32) void {
    var entity_iter_transform = system.query_transform.iterator(struct {
        transform: *fd.Transform,
        fwd: ?*fd.Forward,
        vel: ?*fd.Velocity,
        pos: *const fd.Position,
        rot: *const fd.Rotation,
        scale: *const fd.Scale,
        dynamic: *const fd.Dynamic,
        parent_transform: ?*const fd.Transform,
    });

    const is_actual_frame = dt > 0.00001;
    const dt4: zm.F32x4 = @splat(dt);

    while (entity_iter_transform.next()) |comps| {
        const z_scale_matrix = zm.scaling(comps.scale.x, comps.scale.y, comps.scale.z);
        const z_rot_matrix = zm.matFromQuat(comps.rot.asZM());
        const z_translate_matrix = zm.translation(comps.pos.x, comps.pos.y, comps.pos.z);
        const z_sr_matrix = zm.mul(z_scale_matrix, z_rot_matrix);
        const z_srt_matrix = zm.mul(z_sr_matrix, z_translate_matrix);

        const z_world_matrix = blk: {
            if (comps.parent_transform) |parent_transform| {
                const z_parent_matrix = zm.loadMat43(parent_transform.matrix[0..]);
                const z_world_matrix = zm.mul(z_srt_matrix, z_parent_matrix);
                break :blk z_world_matrix;
            } else {
                break :blk z_srt_matrix;
            }
        };

        if (comps.fwd) |fwd| {
            const z_fwd = zm.util.getAxisZ(z_world_matrix);
            zm.storeArr3(fwd.*.elems(), z_fwd);
        }

        if (is_actual_frame) {
            if (comps.vel) |vel| {
                const pos_prev = zm.loadArr3(comps.transform.getPos00());
                const pos_curr = zm.util.getTranslationVec(z_world_matrix);
                zm.storeArr3(vel.elems(), (pos_curr - pos_prev) / dt4);
            }
        }
        zm.storeMat43(&comps.transform.matrix, z_world_matrix);
    }
}

fn updateCameraMatrices(system: *SystemState) void {
    var entity_iter = system.query_camera.iterator(struct {
        camera: *fd.Camera,
        transform: *fd.Transform,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }

        const z_transform = zm.loadMat43(comps.transform.matrix[0..]);
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
            @as(f32, @floatFromInt(system.renderer.window_width)) / @as(f32, @floatFromInt(system.renderer.window_height)),
            comps.camera.far,
            comps.camera.near,
        );

        zm.storeMat(cam.view[0..], z_view);
        zm.storeMat(cam.projection[0..], z_projection);
        zm.storeMat(cam.view_projection[0..], zm.mul(z_view, z_projection));
    }
}

fn updateCameraFrustum(system: *SystemState) void {
    var entity_iter = system.query_camera.iterator(struct {
        camera: *fd.Camera,
        transform: *fd.Transform,
    });

    while (entity_iter.next()) |comps| {
        var cam = comps.camera;
        if (!cam.active) {
            continue;
        }

        // TODO(gmodarelli): Check if renderer is frozen
        cam.calculateFrustumPlanes();
    }
}

fn updateCameraSwitch(system: *SystemState) void {
    if (system.input_frame_data.just_pressed(config.input.toggle_player_control)) {
        for (system.input_frame_data.map.layer_stack.items) |*layer| {
            if (layer.id.eql(ID("on_foot"))) {
                layer.active = !layer.active;
                var window = system.input_frame_data.window;
                const cursor_mode: zglfw.Cursor.Mode = if (layer.active) .disabled else .normal;
                window.setInputMode(.cursor, cursor_mode);
            }
        }
    }

    if (!system.input_frame_data.just_pressed(config.input.camera_switch)) {
        return;
    }

    system.active_index = 1 - system.active_index;

    var builder = ecsu.QueryBuilder.init(system.ecsu_world);
    _ = builder
        .with(fd.Input)
        .optional(fd.Camera);

    var filter = builder.buildFilter();
    defer filter.deinit();

    var entity_iter = filter.iterator(struct {
        input: *fd.Input,
        cam: ?*fd.Camera,
    });
    while (entity_iter.next()) |comps| {
        var active = false;
        if (comps.input.index == system.active_index) {
            active = true;
        }

        comps.input.active = active;
        if (comps.cam) |cam| {
            cam.active = active;
            if (active) {
                var environment_info = system.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
                environment_info.active_camera = .{ .world = system.ecsu_world.world, .id = entity_iter.entity() };
            }
        }
    }
}
