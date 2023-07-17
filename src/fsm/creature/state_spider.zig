const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../flecs_data.zig");
const fr = @import("../../flecs_relation.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");
const zphy = @import("zphysics");
const egl_math = @import("../../core/math.zig");

pub const NonMovingBroadPhaseLayerFilter = extern struct {
    usingnamespace zphy.BroadPhaseLayerFilter.Methods(@This());
    __v: *const zphy.BroadPhaseLayerFilter.VTable = &vtable,

    const vtable = zphy.BroadPhaseLayerFilter.VTable{
        .shouldCollide = shouldCollide,
    };
    fn shouldCollide(self: *const zphy.BroadPhaseLayerFilter, layer: zphy.BroadPhaseLayer) callconv(.C) bool {
        _ = self;
        if (layer == config.broad_phase_layers.moving) {
            return false;
        }
        return true;
    }
};

fn updateMovement(pos: *fd.Position, rot: *fd.EulerRotation, fwd: *fd.Forward, dt: zm.F32x4, player_pos: *const fd.Position) void {
    _ = fwd;
    _ = rot;
    const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
    var self_pos_z = zm.loadArr3(pos.elems().*);
    const vec_to_player = player_pos_z - self_pos_z;
    const dir_to_player = zm.normalize3(vec_to_player);
    self_pos_z += dir_to_player * dt * zm.f32x4s(0.1);

    zm.store(pos.elems()[0..], self_pos_z, 3);
}

fn updateSnapToTerrain(physics_world: *zphy.PhysicsSystem, pos: *fd.Position, body: *fd.PhysicsBody, player_pos: *const fd.Position) void {
    const query = physics_world.getNarrowPhaseQuery();

    const ray_origin = [_]f32{ pos.x, pos.y + 200, pos.z, 0 };
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };
    const ray = zphy.RRayCast{
        .origin = ray_origin,
        .direction = ray_dir,
    };
    var result = query.castRay(
        ray,
        .{
            .broad_phase_layer_filter = @ptrCast(&NonMovingBroadPhaseLayerFilter{}),
        },
    );

    if (result.has_hit) {
        pos.y = ray_origin[1] + ray_dir[1] * result.hit.fraction;

        const up_z = zm.f32x4(0, 1, 0, 0);

        const body_lock_interface = physics_world.getBodyLockInterfaceNoLock();
        var read_lock_self: zphy.BodyLockRead = .{};
        read_lock_self.lock(body_lock_interface, body.body_id);
        defer read_lock_self.unlock();
        const body_self = read_lock_self.body.?;

        const bodies = physics_world.getBodiesUnsafe();
        const body_hit = zphy.tryGetBody(bodies, result.hit.body_id).?;
        const rot_slope_z = blk: {
            const hit_normal = body_hit.getWorldSpaceSurfaceNormal(result.hit.sub_shape_id, ray.getPointOnRay(result.hit.fraction));
            const hit_normal_z = zm.loadArr3(hit_normal);
            if (hit_normal[1] < 0.99) { // TODO: Find a good value, this was just arbitrarily picked :)
                const rot_axis_z = zm.cross3(up_z, hit_normal_z);
                const dot = zm.dot3(up_z, hit_normal_z)[0];
                const rot_angle = std.math.acos(dot);
                break :blk zm.quatFromAxisAngle(rot_axis_z, rot_angle);
            } else {
                break :blk zm.quatFromAxisAngle(up_z, 0);
            }
        };

        const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
        const self_pos_z = zm.loadArr3(pos.elems().*);
        const vec_to_player = player_pos_z - self_pos_z;
        const dir_to_player = zm.normalize3(vec_to_player);
        const angle_to_player = std.math.atan2(f32, -dir_to_player[2], dir_to_player[0]);
        const rot_towards_player_z = zm.quatFromAxisAngle(up_z, angle_to_player + std.math.pi * 0.5);

        const rot_wanted_z = zm.qmul(rot_towards_player_z, rot_slope_z);
        const rot_curr_z = zm.loadArr4(body_self.getRotation());
        const rot_new_z = zm.slerp(rot_curr_z, rot_wanted_z, 0.01); // TODO SmoothDamp
        const rot_new_normalized_z = zm.normalize4(rot_new_z);
        var rot: [4]f32 = undefined;
        zm.storeArr4(&rot, rot_new_normalized_z);

        // NOTE: Should this use MoveKinematic?
        const body_interface = physics_world.getBodyInterfaceMut();
        body_interface.setPositionRotationAndVelocity(
            body.body_id,
            pos.elems().*,
            rot,
            [3]f32{ 0, 0, 0 },
            [3]f32{ 0, 0, 0 },
        );
    }
}

pub const StateData = struct {
    amount_moved: f32,
    sfx_footstep_index: u32,
};

const StateSpider = struct {
    query: ecsu.Query,
};

fn enter(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StateSpider, ctx.state.self);
    _ = self;
    // const state = ctx.blob_array.getBlobAsValue(comps.fsm.blob_lookup, StateIdle);
    // state.*.amount_moved = 0;
}

fn exit(ctx: fsm.StateFuncContext) void {
    const self = Util.castBytes(StateSpider, ctx.state.self);
    _ = self;
}

fn update(ctx: fsm.StateFuncContext) void {
    // const self = Util.cast(StateIdle, ctx.data.ptr);
    // _ = self;
    const self = Util.castBytes(StateSpider, ctx.state.self);
    var entity_iter = self.query.iterator(struct {
        pos: *fd.Position,
        rot: *fd.EulerRotation,
        fwd: *fd.Forward,
        health: *fd.Health,
        body: *fd.PhysicsBody,
        fsm: *fd.FSM,
    });

    const player_ent = ecs.ecs_lookup(ctx.ecs_world.world, "player");
    const player_pos = ecs.get(ctx.ecs_world, player_ent, fd.Position).?;

    while (entity_iter.next()) |comps| {
        if (entity_iter.entity().id == player_ent) {
            // HACK
            continue;
        }
        const pos_before = comps.pos.*;
        _ = pos_before;
        updateMovement(comps.pos, comps.rot, comps.fwd, ctx.dt, player_pos);
        updateSnapToTerrain(ctx.physics_world, comps.pos, comps.body, player_pos);
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = ecsu.QueryBuilder.init.init(ctx.ecs_world.*);
    _ = query_builder
        .with(fd.Position)
        .with(fd.EulerRotation)
        .with(fd.Forward)
        .with(fd.Health)
        .with(fd.PhysicsBody)
        .with(fd.FSM)
        .without(fd.Input);

    var query = query_builder.buildQuery();
    var self = ctx.allocator.create(StateSpider) catch unreachable;
    self.query = query;

    return .{
        .name = IdLocal.init("spider"),
        .self = std.mem.asBytes(self),
        .size = @sizeOf(StateData),
        .transitions = std.ArrayList(fsm.Transition).init(ctx.allocator),
        .enter = enter,
        .exit = exit,
        .update = update,
    };
}

pub fn destroy() void {}
