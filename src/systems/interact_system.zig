const std = @import("std");
const math = std.math;
const flecs = @import("flecs");
const zm = @import("zmath");
const zphy = @import("zphysics");

const fd = @import("../flecs_data.zig");
const fr = @import("../flecs_relation.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");
const config = @import("../config.zig");
const input = @import("../input.zig");

const SystemState = struct {
    flecs_sys: flecs.EntityId,
    allocator: std.mem.Allocator,
    physics_world: *zphy.PhysicsSystem,
    flecs_world: *flecs.World,
    frame_data: *input.FrameData,

    comp_query_interactor: flecs.Query,
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const flecs_world = ctx.get(config.flecs_world.hash, flecs.World);
    const physics_world = ctx.get(config.physics_world.hash, zphy.PhysicsSystem);
    const frame_data = ctx.get(config.input_frame_data.hash, input.FrameData);

    var query_builder_interactor = flecs.QueryBuilder.init(flecs_world.*);
    _ = query_builder_interactor
        .with(fd.Interactor)
        .with(fd.Transform);
    const comp_query_interactor = query_builder_interactor.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = flecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .flecs_world = flecs_world,
        .physics_world = physics_world,
        .frame_data = frame_data,
        .comp_query_interactor = comp_query_interactor,
    };

    // flecs_world.observer(ObserverCallback, .on_set, system);

    // initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_interactor.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *flecs.Iterator(fd.NOCOMP)) void {
    var system = @ptrCast(*SystemState, @alignCast(@alignOf(SystemState), iter.iter.ctx));
    updateInteractors(system);
    // updatePatches(system);
}

fn updateInteractors(system: *SystemState) void {
    var entity_iter = system.comp_query_interactor.iterator(struct {
        Interactor: *fd.Interactor,
        transform: *fd.Transform,
    });

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    _ = arena;

    const wielded_use_primary_held = system.frame_data.held(config.input_wielded_use_primary);
    const wielded_use_primary_released = system.frame_data.held(config.input_wielded_use_primary);
    while (entity_iter.next()) |comps| {
        var interactor_comp = comps.Interactor;

        const item_ent = flecs.Entity.init(system.flecs_world.world, interactor_comp.wielded_item_ent_id);
        var weapon_comp = item_ent.getMut(fd.ProjectileWeapon).?;

        if (weapon_comp.chambered_projectile == 0) {
            // Load new projectile
            var proj_ent = system.flecs_world.newEntity();
            proj_ent.setName("arrow");
            proj_ent.set(fd.Position{ .x = 0, .y = 0, .z = -0.5 });
            proj_ent.set(fd.EulerRotation{});
            proj_ent.set(fd.Scale.createScalar(1));
            proj_ent.set(fd.Transform{});
            proj_ent.set(fd.Forward{});
            proj_ent.set(fd.Dynamic{});
            proj_ent.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("bow"),
                .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 1.0, .roughness = 1.0 },
            });
            proj_ent.childOf(item_ent);
            weapon_comp.chambered_projectile = proj_ent.id;
        }

        var proj_ent = flecs.Entity.init(system.flecs_world.world, weapon_comp.chambered_projectile);
        var item_rotation = item_ent.getMut(fd.EulerRotation).?;
        const item_transform = item_ent.get(fd.Transform).?;
        const target_roll: f32 = if (wielded_use_primary_held) 1 else 0;
        item_rotation.pitch = zm.lerpV(item_rotation.roll, target_roll, 0.1);
        if (wielded_use_primary_released) {
            // Shoot arrow

            weapon_comp.chambered_projectile = 0;
            proj_ent.removePair(flecs.c.Constants.EcsChildOf, item_ent);

            const body_interface = system.physics_world.getBodyInterfaceMut();

            const proj_transform = proj_ent.get(fd.Transform).?;
            const proj_pos_world = proj_transform.getPos00();
            const proj_rot_world = proj_transform.getRotPitchRollYaw();

            const proj_shape_settings = zphy.BoxShapeSettings.create(.{ 0.01, 0.01, 1.0 }) catch unreachable;
            defer proj_shape_settings.release();

            const proj_shape = proj_shape_settings.createShape() catch unreachable;
            defer proj_shape.release();

            const proj_body_id = body_interface.createAndAddBody(.{
                .position = .{ proj_pos_world[0], proj_pos_world[1], proj_pos_world[2], 0 },
                .rotation = .{ proj_rot_world[0], proj_rot_world[1], proj_rot_world[2], 0 },
                .shape = proj_shape,
                .motion_type = .dynamic,
                .object_layer = config.object_layers.moving,
            }, .activate) catch unreachable;

            //  Assign to flecs component
            proj_ent.set(fd.PhysicsBody{ .body_id = proj_body_id });

            // Send it flying
            const world_transform_z = zm.loadMat43(&item_transform.matrix);
            const forward_z = zm.util.getAxisZ(world_transform_z);
            const velocity_z = forward_z * zm.f32x4s(10);
            var velocity: [3]f32 = undefined;
            zm.storeArr3(&velocity, velocity_z);
            body_interface.setLinearVelocity(proj_body_id, velocity);
        } else if (wielded_use_primary_held) {
            // Pull string
            var proj_pos = proj_ent.getMut(fd.Position).?;
            proj_pos.z = zm.lerpV(proj_pos.z, -0.3, 0.01);
        } else {
            // Relax string
            var proj_pos = proj_ent.getMut(fd.Position).?;
            proj_pos.z = zm.lerpV(proj_pos.z, 0, 0.1);
        }
    }
}
