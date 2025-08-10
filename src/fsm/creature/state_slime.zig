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
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 6);
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "fsm_enemy_slime",
            ecs.OnUpdate,
            &system_desc,
        );
    }
}

fn rotateTowardsPlayer(
    pos: *fd.Position,
    rot: *fd.Rotation,
    player_pos: *const fd.Position,
) void {
    const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
    const self_pos_z = zm.loadArr3(pos.elems().*);
    const vec_to_player = player_pos_z - self_pos_z;
    const dist_to_player_sq = zm.lengthSq3(vec_to_player)[0];
    if (dist_to_player_sq > 1) {
        const up_z = zm.f32x4(0, 1, 0, 0);
        const skitter = dist_to_player_sq > (15 * 15) and std.math.modf(player_pos.y + pos.y * 0.25).fpart > 0.25;
        const dir_to_player = zm.normalize3(vec_to_player);
        const skitter_angle_offset: f32 = if (skitter) std.math.modf(player_pos.y + pos.y * 0.25).fpart * 3 - 1.5 else 0;
        const angle_to_player = std.math.atan2(dir_to_player[0], dir_to_player[2]) + skitter_angle_offset;
        const rot_towards_player_z = zm.quatFromAxisAngle(up_z, angle_to_player);

        const rot_curr_z = rot.asZM();
        const slerp_factor: f32 = if (skitter) 0.1 else 0.1;
        const rot_new_z = zm.slerp(rot_curr_z, rot_towards_player_z, slerp_factor); // TODO SmoothDamp
        const rot_new_normalized_z = zm.normalize4(rot_new_z);
        zm.storeArr4(rot.elems(), rot_new_normalized_z);
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

    const player_ent = ecs.lookup(ctx.ecsu_world.world, "main_player");
    const player_pos = ecs.get(ctx.ecsu_world.world, player_ent, fd.Position).?;
    const body_interface = ctx.physics_world.getBodyInterfaceMut();

    const environment_info = ctx.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
    const world_time = environment_info.world_time;

    for (positions, rotations, forwards, bodies, scales, it.entities()) |*pos, *rot, *fwd, *body, *scale, ent| {
        _ = fwd; // autofix
        if (!lol) {
            lol = true;
            ctx.task_queue.registerTaskType(.{
                .id = SlimeDropTask.id,
                .setup = &SlimeDropTask.setup,
                .calculate = &SlimeDropTask.calculate,
                .apply = &SlimeDropTask.apply,
            });
            ctx.task_queue.enqueue(SlimeDropTask.id, 5, SlimeDropTask{ .entity = ent });
            ctx.task_queue.enqueue(SlimeDropTask.id, 20, SlimeDropTask{ .entity = ent });
            ctx.task_queue.enqueue(SlimeDropTask.id, 30, SlimeDropTask{ .entity = ent });
            ctx.task_queue.enqueue(SlimeDropTask.id, 40, SlimeDropTask{ .entity = ent });
            ctx.task_queue.enqueue(SlimeDropTask.id, 50, SlimeDropTask{ .entity = ent });
            ctx.task_queue.enqueue(SlimeDropTask.id, 100, SlimeDropTask{ .entity = ent });
        }
        if (body_interface.getMotionType(body.body_id) == .kinematic) {
            scale.x = @floatCast(10 + math.sin(world_time * 3.5) * 1.5);
            scale.y = @floatCast(10 + math.sin(world_time * 0.3) * 0.7 + math.cos(world_time * 0.5) * 0.7);
            scale.z = @floatCast(10 + math.cos(world_time * 2.3) * 1.5);

            rotateTowardsPlayer(pos, rot, player_pos);
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
    pos: [3]f32 = undefined,

    fn setup(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = ctx; // autofix
        _ = data; // autofix
        _ = allocator; // autofix
        // var self: *SlimeDropTask = @ptrCast(data);
        // const pos = ctx.ecsu_world.get(self.entity, fd.Position);
        // self.pos = pos.elemsConst().*;
    }

    fn calculate(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = allocator; // autofix
        var self: *SlimeDropTask = @alignCast(@ptrCast(data));
        const pos = ecs.get(ctx.ecsu_world.world, self.entity, fd.Position).?;
        self.pos = pos.elemsConst().*;
    }

    fn apply(ctx: task_queue.TaskContext, data: []u8, allocator: std.mem.Allocator) void {
        _ = allocator; // autofix

        const self: *SlimeDropTask = @alignCast(@ptrCast(data));
        {
            var ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, config.prefab.slime);
            const spawn_pos = self.pos;
            ent.set(fd.Position{
                .x = spawn_pos[0],
                .y = spawn_pos[1],
                .z = spawn_pos[2],
            });

            ent.set(fd.Scale.create(3, 0.1, 3));

            ent.set(fd.PointLight{
                .color = .{ .r = 0.2, .g = 0.2, .b = 0.9 },
                .range = 60.0,
                .intensity = 50.0,
            });
        }
    }
};
