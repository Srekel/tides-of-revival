const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const IdLocal = @import("../../variant.zig").IdLocal;
const Util = @import("../../util.zig");
const BlobArray = @import("../../blob_array.zig").BlobArray;
const fsm = @import("../fsm.zig");
const fd = @import("../../flecs_data.zig");
const fr = @import("../../flecs_relation.zig");
const zm = @import("zmath");
const input = @import("../../input.zig");
const config = @import("../../config.zig");
const zphy = @import("zphysics");
const egl_math = @import("../../core/math.zig");

fn updateMovement(pos: *fd.Position, rot: *fd.EulerRotation, fwd: *fd.Forward, dt: zm.F32x4, player_pos: *const fd.Position) void {
    _ = fwd;
    _ = rot;
    const player_pos_z = zm.loadArr3(player_pos.elemsConst().*);
    var self_pos_z = zm.loadArr3(pos.elems().*);
    const vec_to_player = player_pos_z - self_pos_z;
    const dir_to_player = zm.normalize3(vec_to_player);
    self_pos_z += dir_to_player * dt * zm.f32x4s(0.2);

    zm.store(pos.elems()[0..], self_pos_z, 3);
}

fn updateSnapToTerrain(physics_world: *zphy.PhysicsSystem, pos: *fd.Position) void {
    const query = physics_world.getNarrowPhaseQuery();

    const ray_origin = [_]f32{ pos.x, pos.y + 200, pos.z, 0 };
    const ray_dir = [_]f32{ 0, -1000, 0, 0 };
    var result = query.castRay(.{
        .origin = ray_origin,
        .direction = ray_dir,
    }, .{});

    if (result.has_hit) {
        pos.y = ray_origin[1] + ray_dir[1] * result.hit.fraction;
    }
}

pub const StateData = struct {
    amount_moved: f32,
    sfx_footstep_index: u32,
};

const StateSpider = struct {
    query: flecs.Query,
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
        fsm: *fd.FSM,
    });

    const player_ent_id = flecs.c.ecs_lookup(ctx.flecs_world.world, "player");
    const player_ent = flecs.Entity{ .id = player_ent_id, .world = ctx.flecs_world.world };
    const player_pos = player_ent.get(fd.Position).?;

    while (entity_iter.next()) |comps| {
        if (entity_iter.entity().id == player_ent_id) {
            // HACK
            continue;
        }
        const pos_before = comps.pos.*;
        _ = pos_before;
        updateMovement(comps.pos, comps.rot, comps.fwd, ctx.dt, player_pos);
        updateSnapToTerrain(ctx.physics_world, comps.pos);
    }
}

pub fn create(ctx: fsm.StateCreateContext) fsm.State {
    var query_builder = flecs.QueryBuilder.init(ctx.flecs_world.*);
    _ = query_builder
        .with(fd.Position)
        .with(fd.EulerRotation)
        .with(fd.Forward)
        .with(fd.Health)
        .with(fd.FSM)
        .without(fd.Camera);

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
