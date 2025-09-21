const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const IdLocal = @import("../../core/core.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../core/blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const fr = @import("../../config/flecs_relation.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config/config.zig");
const zphy = @import("zphysics");
const egl_math = @import("../../core/math.zig");
const context = @import("../../core/context.zig");
const task_queue = @import("../../core/task_queue.zig");
const im3d = @import("im3d");

pub const StateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    task_queue: *task_queue.TaskQueue,
};

pub fn create(create_ctx: StateContext) void {
    const update_ctx = create_ctx.arena_system_lifetime.create(StateContext) catch unreachable;
    update_ctx.* = StateContext.view(create_ctx);

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = fsm_enemy_slime;
        system_desc.ctx = update_ctx;
        system_desc.query.terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Position), .inout = .InOut },
            .{ .id = ecs.id(fd.Rotation), .inout = .InOut },
            .{ .id = ecs.id(fd.Forward), .inout = .InOut },
            .{ .id = ecs.id(fd.PhysicsBody), .inout = .InOut },
            .{ .id = ecs.pair(fd.FSM_ENEMY, fd.FSM_ENEMY_Slime), .inout = .InOut },
            .{ .id = ecs.id(fd.Scale), .inout = .InOut },
            .{ .id = ecs.id(fd.Locomotion), .inout = .InOut },
            .{ .id = ecs.id(fd.Enemy), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 8);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "fsm_enemy_slime",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn rotateTowardsTarget(
    pos: *fd.Position,
    rot: *fd.Rotation,
    locomotion: *fd.Locomotion,
    enemy: *const fd.Enemy,
    target_pos: [3]f32,
) void {
    const player_pos_z = zm.loadArr3(target_pos);
    const self_pos_z = zm.loadArr3(pos.elems().*);
    const vec_to_player = player_pos_z - self_pos_z;
    const dist_to_player_sq = zm.lengthSq3(vec_to_player)[0];
    if (dist_to_player_sq > 1) {
        const up_z = zm.f32x4(0, 1, 0, 0);
        const skitter = !enemy.idling and dist_to_player_sq > (40 * 40) and std.math.modf(target_pos[1] + pos.y * 0.125).fpart > 0.25;
        const dir_to_player = zm.normalize3(vec_to_player);
        const skitter_angle_offset: f32 = if (skitter) if (enemy.left_bias) -1.5 else 1.5 else 0;
        const angle_to_player = std.math.atan2(dir_to_player[0], dir_to_player[2]) + skitter_angle_offset;
        const rot_towards_player_z = zm.quatFromAxisAngle(up_z, angle_to_player);

        const rot_curr_z = rot.asZM();
        const slerp_factor: f32 = if (skitter) 0.05 else 0.1;
        const rot_new_z = zm.slerp(rot_curr_z, rot_towards_player_z, slerp_factor); // TODO SmoothDamp
        const rot_new_normalized_z = zm.normalize4(rot_new_z);
        zm.storeArr4(rot.elems(), rot_new_normalized_z);

        if (!locomotion.affected_by_gravity and enemy.aggressive) {
            locomotion.speed = if (skitter) 20 / enemy.base_scale else 8 / enemy.base_scale;
        }
    }
}

fn updateTargetPosition(
    pos: *fd.Position,
    fwd: *fd.Forward,
    locomotion: *fd.Locomotion,
    physics_world_low: *zphy.PhysicsSystem,
) void {
    if (locomotion.target_position == null) {
        locomotion.target_position = pos.elemsConst().*;
        locomotion.target_position.?[1] += 10;
    }
    const cast_ray_args: zphy.NarrowPhaseQuery.CastRayArgs = .{
        .broad_phase_layer_filter = @ptrCast(&config.physics.NonMovingBroadPhaseLayerFilter{}),
    };

    // im3d.Im3d.DrawCone(
    //     &.{
    //         .x = locomotion.target_position.?[0],
    //         .y = locomotion.target_position.?[1],
    //         .z = locomotion.target_position.?[2],
    //     },
    //     &.{ .x = 0, .y = 1, .z = 0 },
    //     20,
    //     3,
    //     3,
    // );
    // im3d.Im3d.DrawArrow(
    //     &.{ .x = pos.x, .y = pos.y, .z = pos.z },
    //     &.{
    //         .x = locomotion.target_position.?[0],
    //         .y = locomotion.target_position.?[1],
    //         .z = locomotion.target_position.?[2],
    //     },
    //     .{},
    // );

    const self_pos_z = zm.loadArr3(pos.elems().*);
    const target_pos_z = zm.loadArr3(locomotion.target_position.?);
    const vec_to_target = (target_pos_z - self_pos_z) * zm.Vec{ 1, 0, 1, 0 };
    const dist_to_target_sq = zm.lengthSq3(vec_to_target)[0];
    if (dist_to_target_sq > 180 * 180) {
        return;
    }

    const angle_curr = math.atan2(fwd.z, fwd.x);
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };

    var best_target = [3]f32{ 0, -1000, 0 };

    const angles = 5;
    for (0..angles) |i_angle| {
        const i_angle_f: f32 = @as(f32, @floatFromInt(i_angle)) - @as(f32, angles / 2);
        const angle_offset = i_angle_f * math.degreesToRadians(5);
        const angle = angle_curr + angle_offset;

        const pos_offset = [_]f32{
            std.math.cos(angle) * 200,
            0,
            std.math.sin(angle) * 200,
        };

        const sample_pos = [_]f32{
            pos.x + pos_offset[0],
            pos.y + pos_offset[1],
            pos.z + pos_offset[2],
        };

        const ray_origin = [_]f32{
            sample_pos[0],
            sample_pos[1] + 500,
            sample_pos[2],
            0,
        };
        const ray = zphy.RRayCast{
            .origin = ray_origin,
            .direction = ray_dir,
        };

        var query = physics_world_low.getNarrowPhaseQuery();
        const result = query.castRay(ray, cast_ray_args);
        if (!result.has_hit) {
            continue;
        }
        const height = ray_origin[1] + ray_dir[1] * result.hit.fraction;
        std.log.info("lol {d}", .{height});

        // im3d.Im3d.DrawCone(
        //     &.{
        //         .x = sample_pos[0],
        //         .y = height,
        //         .z = sample_pos[2],
        //     },
        //     &.{ .x = 0, .y = 1, .z = 0 },
        //     20,
        //     3,
        //     3,
        // );

        if (height > best_target[1]) {
            best_target = .{
                ray_origin[0],
                height,
                ray_origin[2],
            };
        }
    }

    if (best_target[1] > config.ocean_level and best_target[1] < 450) {
        locomotion.target_position = best_target;
    } else {
        const dir_to_center = .{
            config.world_center3[0] - pos.x,
            config.world_center3[1] - pos.y,
            config.world_center3[2] - pos.z,
        };

        locomotion.target_position = .{
            pos.x + dir_to_center[0] * 0.3,
            pos.y,
            pos.z + dir_to_center[2] * 0.3,
        };
        // locomotion.target_position = .{
        //     pos.x - fwd.x * 200,
        //     pos.y,
        //     pos.z - fwd.z * 200,
        // };
    }
}

var lol = false;
fn fsm_enemy_slime(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *StateContext = @ptrCast(@alignCast(it.ctx));

    const positions = ecs.field(it, fd.Position, 0).?;
    const rotations = ecs.field(it, fd.Rotation, 1).?;
    const forwards = ecs.field(it, fd.Forward, 2).?;
    const bodies = ecs.field(it, fd.PhysicsBody, 3).?;
    const scales = ecs.field(it, fd.Scale, 5).?;
    const locomotions = ecs.field(it, fd.Locomotion, 6).?;
    const enemies = ecs.field(it, fd.Enemy, 7).?;

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_pos = ecs.get(ctx.ecsu_world.world, player_ent, fd.Position).?;
    const body_interface = ctx.physics_world.getBodyInterfaceMut();

    const environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const world_time = environment_info.world_time;

    for (positions, rotations, forwards, bodies, scales, locomotions, enemies, it.entities()) |*pos, *rot, *fwd, *body, *scale, *locomotion, enemy, ent| {
        if (!lol) {
            lol = true;
            ctx.task_queue.registerTaskType(.{
                .id = SlimeDropTask.id,
                .setup = &SlimeDropTask.setup,
                .calculate = &SlimeDropTask.calculate,
                .validate = &SlimeDropTask.validate,
                .apply = &SlimeDropTask.apply,
            });

            ctx.task_queue.registerTaskType(.{
                .id = DieTask.id,
                .setup = &DieTask.setup,
                .calculate = &DieTask.calculate,
                .validate = task_queue.alwaysValid,
                .apply = &DieTask.apply,
            });
            ctx.task_queue.registerTaskType(.{
                .id = SplitIfNearPlayer.id,
                .setup = &SplitIfNearPlayer.setup,
                .calculate = &SplitIfNearPlayer.calculate,
                .validate = SplitIfNearPlayer.validate,
                .apply = &SplitIfNearPlayer.apply,
            });
            {
                const task_data = ctx.task_queue.allocateTaskData(5, SlimeDropTask);
                task_data.*.entity = ent;
                ctx.task_queue.enqueue(
                    SlimeDropTask.id,
                    .{ .time = 5, .loop_type = .{ .loop = 60 } },
                    std.mem.asBytes(task_data),
                );
            }
            {
                const task_data = ctx.task_queue.allocateTaskData(5, SlimeDropTask);
                task_data.*.entity = ent;
                ctx.task_queue.enqueue(
                    SplitIfNearPlayer.id,
                    .{ .time = 1, .loop_type = .{ .loop = 2.4 } },
                    std.mem.asBytes(task_data),
                );
            }
        }

        if (body_interface.getMotionType(body.body_id) == .kinematic) {
            const jiggle = 0.1 + 0.1 * 1.0 / enemy.base_scale;
            scale.x = @floatCast(enemy.base_scale * (1 + math.sin(world_time * 3.5) * jiggle));
            scale.y = @floatCast(enemy.base_scale * (1 + math.sin(world_time * 0.3) * 0.05 + math.cos(world_time * 0.5) * 0.05));
            scale.z = @floatCast(enemy.base_scale * (1 + math.cos(world_time * 2.3) * jiggle));

            if (enemy.aggressive) {
                locomotion.target_position = player_pos.elemsConst().*;
            } else {
                updateTargetPosition(pos, fwd, locomotion, ctx.physics_world_low);
            }

            if (!locomotion.affected_by_gravity) {
                rotateTowardsTarget(pos, rot, locomotion, &enemy, locomotion.target_position.?);
            }
            // rotateTowardsTarget(pos, rot, player_pos.elemsConst().*);
        }
    }
}

// ████████╗ █████╗ ███████╗██╗  ██╗███████╗
// ╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝██╔════╝
//    ██║   ███████║███████╗█████╔╝ ███████╗
//    ██║   ██╔══██║╚════██║██╔═██╗ ╚════██║
//    ██║   ██║  ██║███████║██║  ██╗███████║
//    ╚═╝   ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝

const SlimeDropTask = struct {
    const id = IdLocal.init("SlimeDropTask");

    entity: ecs.entity_t,
    pos: ?[3]f32 = null,

    fn setup(ctx: task_queue.TaskContext, task_data: []u8, allocator: std.mem.Allocator) void {
        _ = allocator; // autofix
        var self: *SlimeDropTask = @alignCast(@ptrCast(task_data));
        if (ecs.is_alive(ctx.ecsu_world.world, self.entity)) {
            const pos = ecs.get(ctx.ecsu_world.world, self.entity, fd.Position).?;
            self.pos = pos.elemsConst().*;
        }
    }

    fn calculate(ctx: task_queue.TaskContext, task_data: []u8, allocator: std.mem.Allocator) void {
        _ = ctx; // autofix
        _ = task_data; // autofix
        _ = allocator; // autofix
    }

    fn validate(ctx: task_queue.TaskContext, task_data: []u8, allocator: std.mem.Allocator) task_queue.TaskValidity {
        _ = ctx; // autofix
        _ = allocator; // autofix
        const self: *SlimeDropTask = @alignCast(@ptrCast(task_data));
        if (self.pos == null) {
            return .remove;
        }
        return .valid;
    }

    fn apply(ctx: task_queue.TaskContext, task_data: []u8, allocator: std.mem.Allocator) void {
        _ = allocator; // autofix

        const self: *SlimeDropTask = @alignCast(@ptrCast(task_data));
        {
            var ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, config.prefab.slime_trail);
            const spawn_pos = self.pos.?;
            const rot = ecs.get(ctx.ecsu_world.world, self.entity, fd.Rotation).?.*;

            ent.set(fd.Position{
                .x = spawn_pos[0],
                .y = spawn_pos[1],
                .z = spawn_pos[2],
            });

            ent.set(fd.Scale.create(1, 1, 1));
            ent.set(rot);
            ent.set(fd.Transform{});
            ent.set(fd.Dynamic{});

            const light_ent = ctx.ecsu_world.newEntity();
            light_ent.childOf(ent);
            light_ent.set(fd.Position{ .x = 0, .y = 15, .z = 0 });
            light_ent.set(fd.Rotation{});
            light_ent.set(fd.Scale.createScalar(1));
            light_ent.set(fd.Transform{});
            light_ent.set(fd.Dynamic{});

            light_ent.set(fd.PointLight{
                .color = .{ .r = 0.2, .g = 1, .b = 0.3 },
                .range = 30,
                .intensity = 10,
            });

            const task_data_die = ctx.task_queue.allocateTaskData(3600, DieTask);
            task_data_die.*.entity = ent.id;
            ctx.task_queue.enqueue(
                DieTask.id,
                .{ .time = ctx.time.now + 3600, .loop_type = .once },
                std.mem.asBytes(task_data_die),
            );
        }
    }
};

const DieTask = struct {
    const id = IdLocal.init("DieTask");

    entity: ecs.entity_t,

    fn setup(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = ctx; // autofix
        _ = data; // autofix
        _ = allocator; // autofix
    }

    fn calculate(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = ctx; // autofix
        _ = data; // autofix
        _ = allocator; // autofix
    }

    fn apply(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = allocator; // autofix

        const self: *SlimeDropTask = @alignCast(@ptrCast(data));
        ecs.delete(ctx.ecsu_world.world, self.entity);
    }
};

const SplitIfNearPlayer = struct {
    const id = IdLocal.init("DieTask");

    entity: ecs.entity_t,

    fn setup(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = ctx; // autofix
        _ = data; // autofix
        _ = allocator; // autofix
    }

    fn calculate(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = ctx; // autofix
        _ = data; // autofix
        _ = allocator; // autofix
    }

    fn validate(ctx: task_queue.TaskContext, task_data: []u8, allocator: std.mem.Allocator) task_queue.TaskValidity {
        _ = allocator; // autofix
        const self: *SlimeDropTask = @alignCast(@ptrCast(task_data));
        const enemy_opt = ecs.get(ctx.ecsu_world.world, self.entity, fd.Enemy);
        if (enemy_opt == null) {
            return .remove;
        }
        const enemy = enemy_opt.?;

        const locomotion = ecs.get(ctx.ecsu_world.world, self.entity, fd.Locomotion).?;
        if (enemy.base_scale <= 1.2) {
            return .remove;
        }

        if (locomotion.affected_by_gravity) {
            return .reschedule;
        }

        if (enemy.aggressive) {
            return .valid;
        }

        const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
        const player_pos = ecs.get(ctx.ecsu_world.world, player_ent, fd.Position).?;
        const self_pos = ecs.get(ctx.ecsu_world.world, self.entity, fd.Position).?;

        const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
        const self_pos_z = zm.loadArr3(self_pos.elemsConst().*);
        if (zm.length3(player_pos_z - self_pos_z)[0] < 200) {
            return .valid;
        }
        return .reschedule;
    }

    fn apply(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = allocator; // autofix

        const self: *SlimeDropTask = @alignCast(@ptrCast(data));
        var enemy = ecs.get_mut(ctx.ecsu_world.world, self.entity, fd.Enemy).?;
        enemy.base_scale *= 0.8;
        enemy.aggressive = true;
        enemy.idling = false;

        var health = ecs.get_mut(ctx.ecsu_world.world, self.entity, fd.Health).?;
        health.value = enemy.base_scale * enemy.base_scale * enemy.base_scale;

        var pos = ecs.get(ctx.ecsu_world.world, self.entity, fd.Position).?.*;
        pos.y += 5;

        var ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, config.prefab.slime);
        ent.set(pos);

        const base_scale = enemy.base_scale * 0.6;
        const rot = fd.Rotation.initFromEulerDegrees(0, std.crypto.random.float(f32) * 360, 0);
        ent.set(fd.Scale.create(1, 1, 1));
        ent.set(rot);
        ent.set(fd.Transform{});
        ent.set(fd.Dynamic{});
        ent.set(fd.Locomotion{
            .affected_by_gravity = true,
            .speed = 15 + std.crypto.random.float(f32) * enemy.base_scale,
            .speed_y = 15 + std.crypto.random.float(f32) * enemy.base_scale,
        });
        ent.set(fd.Enemy{
            .base_scale = base_scale,
            .aggressive = true,
            .idling = false,
            .left_bias = std.crypto.random.float(f32) > 0.5,
        });
        ent.addPair(fd.FSM_ENEMY, fd.FSM_ENEMY_Slime);
        ent.set(fd.Health{ .value = 10 * base_scale * base_scale });

        const body_interface = ctx.physics_world.getBodyInterfaceMut();

        const shape_settings = zphy.SphereShapeSettings.create(1.5 * 1) catch unreachable;
        defer shape_settings.release();

        const root_shape_settings = zphy.DecoratedShapeSettings.createRotatedTranslated(
            &shape_settings.asShapeSettings().*,
            rot.elemsConst().*,
            .{ 0, 0, 0 },
        ) catch unreachable;
        defer root_shape_settings.release();
        const root_shape = root_shape_settings.createShape() catch unreachable;

        const body_id = body_interface.createAndAddBody(.{
            .position = .{ pos.x, pos.y, pos.z, 0 },
            .rotation = rot.elemsConst().*,
            .shape = root_shape,
            .motion_type = .kinematic,
            .object_layer = config.physics.object_layers.moving,
            .motion_quality = .discrete,
            .user_data = ent.id,
            .angular_damping = 0.975,
            .inertia_multiplier = 10,
            .friction = 0.5,
        }, .activate) catch unreachable;
        ent.set(fd.PhysicsBody{ .body_id = body_id, .shape_opt = root_shape });

        {
            const task_data = ctx.task_queue.allocateTaskData(5, SlimeDropTask);
            task_data.*.entity = ent.id;
            ctx.task_queue.enqueue(
                SplitIfNearPlayer.id,
                .{
                    .time = enemy.base_scale * 2 + std.crypto.random.float(f64) * 2,
                    .loop_type = .{ .loop = enemy.base_scale * 0.5 + std.crypto.random.float(f64) },
                },
                std.mem.asBytes(task_data),
            );
        }

        const light_ent = ctx.ecsu_world.newEntity();
        light_ent.childOf(ent);
        light_ent.set(fd.Position{ .x = 0, .y = 15, .z = 0 });
        light_ent.set(fd.Rotation.initFromEulerDegrees(0, std.crypto.random.float(f32), 0));
        light_ent.set(fd.Scale.createScalar(1));
        light_ent.set(fd.Transform{});
        light_ent.set(fd.Dynamic{});

        light_ent.set(fd.PointLight{
            .color = .{ .r = 0.2, .g = 1, .b = 0.3 },
            .range = 20,
            .intensity = 5,
        });
    }
};
