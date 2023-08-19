const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../flecs_data.zig");
const fr = @import("../flecs_relation.zig");
const IdLocal = @import("../variant.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");
const config = @import("../config.zig");
const input = @import("../input.zig");
const EventManager = @import("../core/event_manager.zig").EventManager;

const SystemState = struct {
    flecs_sys: ecs.entity_t,
    allocator: std.mem.Allocator,
    physics_world: *zphy.PhysicsSystem,
    ecsu_world: ecsu.World,
    frame_data: *input.FrameData,
    event_manager: *EventManager,

    comp_query_interactor: ecsu.Query,
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const ecsu_world = ctx.get(config.ecsu_world.hash, ecsu.World).*;
    const physics_world = ctx.get(config.physics_world.hash, zphy.PhysicsSystem);
    const frame_data = ctx.get(config.input_frame_data.hash, input.FrameData);
    const event_manager = ctx.get(config.event_manager.hash, EventManager);

    var query_builder_interactor = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_interactor
        .with(fd.Interactor)
        .with(fd.Transform);
    const comp_query_interactor = query_builder_interactor.buildQuery();

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .physics_world = physics_world,
        .frame_data = frame_data,
        .event_manager = event_manager,
        .comp_query_interactor = comp_query_interactor,
    };

    // ecsu_world.observer(OnCollideObserverCallback, fd.PhysicsBody, system);
    // ecsu_world.observer(OnCollideObserverCallback, config.events.onCollisionEvent(ecsu_world.world), system);
    event_manager.registerListener(config.events.frame_collisions_id, onEventFrameCollisions, system);

    // initStateData(system);
    return system;
}

pub fn destroy(system: *SystemState) void {
    system.comp_query_interactor.deinit();
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    updateInteractors(system, iter.iter.delta_time);
}

fn updateInteractors(system: *SystemState, dt: f32) void {
    _ = dt;
    var entity_iter = system.comp_query_interactor.iterator(struct {
        interactor: *fd.Interactor,
        transform: *fd.Transform,
    });

    const wielded_use_primary_held = system.frame_data.held(config.input_wielded_use_primary);
    const wielded_use_primary_released = system.frame_data.just_released(config.input_wielded_use_primary);
    while (entity_iter.next()) |comps| {
        var interactor_comp = comps.interactor;

        const item_ent_id = interactor_comp.wielded_item_ent_id;
        var weapon_comp = ecs.get_mut(system.ecsu_world.world, item_ent_id, fd.ProjectileWeapon).?;

        if (weapon_comp.chambered_projectile == 0) {
            // Load new projectile
            var proj_ent = system.ecsu_world.newEntity();
            // proj_ent.setName("arrow");
            proj_ent.set(fd.Position{ .x = -0.03, .y = 0, .z = -0.5 });
            proj_ent.set(fd.Rotation{});
            proj_ent.set(fd.Scale.createScalar(1));
            proj_ent.set(fd.Transform.initFromPosition(.{ .x = -0.03, .y = 0, .z = -0.5 }));
            proj_ent.set(fd.Forward{});
            proj_ent.set(fd.Dynamic{});
            proj_ent.set(fd.Projectile{});
            proj_ent.set(fd.CIShapeMeshInstance{
                .id = IdLocal.id64("arrow"),
                .basecolor_roughness = .{ .r = 1.0, .g = 1.0, .b = 1.0, .roughness = 1.0 },
            });
            proj_ent.childOf(item_ent_id);
            weapon_comp.chambered_projectile = proj_ent.id;
            return;
        }

        var proj_ent = ecsu.Entity.init(system.ecsu_world.world, weapon_comp.chambered_projectile);
        var item_rotation = ecs.get_mut(system.ecsu_world.world, item_ent_id, fd.Rotation).?;
        var axis = zm.f32x4s(0);
        var angle: f32 = 0;
        zm.quatToAxisAngle(item_rotation.asZM(), &axis, &angle);
        const target_roll_angle: f32 = if (wielded_use_primary_held) -1 else 0;
        const target_rot_z = zm.quatFromNormAxisAngle(config.ROLL_Z, target_roll_angle);
        const final_rot_z = zm.slerp(item_rotation.asZM(), target_rot_z, 0.1);
        item_rotation.fromZM(final_rot_z);

        if (wielded_use_primary_released) {
            // Shoot arrow
            // std.debug.print("RELEASE\n", .{});
            const charge = weapon_comp.charge;
            weapon_comp.charge = 0;

            // state.physics_world.optimizeBroadPhase();
            weapon_comp.chambered_projectile = 0;
            proj_ent.removePair(ecs.ChildOf, item_ent_id);

            const body_interface = system.physics_world.getBodyInterfaceMut();

            const proj_transform = proj_ent.get(fd.Transform).?;
            const proj_pos_world = proj_transform.getPos00();
            const proj_rot_world = proj_transform.getRotQuaternion();
            const proj_rot_world_flip_z = zm.quatFromAxisAngle(zm.f32x4(0.0, 1.0, 0.0, 0.0), std.math.pi);
            const proj_rot_world_z = zm.qmul(proj_rot_world_flip_z, zm.loadArr4(proj_rot_world));
            var proj_rot_world_physics: [4]f32 = undefined;
            zm.storeArr4(&proj_rot_world_physics, proj_rot_world_z);

            const proj_shape_settings = zphy.BoxShapeSettings.create(.{ 0.15, 0.15, 1.0 }) catch unreachable;
            defer proj_shape_settings.release();

            const proj_shape = proj_shape_settings.createShape() catch unreachable;
            defer proj_shape.release();

            const proj_body_id = body_interface.createAndAddBody(.{
                .position = .{ proj_pos_world[0], proj_pos_world[1], proj_pos_world[2], 0 },
                .rotation = proj_rot_world_physics,
                .shape = proj_shape,
                .motion_type = .dynamic,
                .object_layer = config.object_layers.moving,
                .motion_quality = .linear_cast,
                .user_data = proj_ent.id,
            }, .activate) catch unreachable;

            //  Assign to flecs component
            proj_ent.set(fd.PhysicsBody{ .body_id = proj_body_id });

            // Send it flying
            const item_transform = ecs.get(system.ecsu_world.world, item_ent_id, fd.Transform).?;
            const world_transform_z = zm.loadMat43(&item_transform.matrix);
            const forward_z = zm.util.getAxisZ(world_transform_z);
            const up_z = zm.f32x4(0, 1, 0, 0);
            const velocity_z = forward_z * zm.f32x4s(15 + charge * 30) + up_z * zm.f32x4s(charge);
            var velocity: [3]f32 = undefined;
            zm.storeArr3(&velocity, velocity_z);
            body_interface.setLinearVelocity(proj_body_id, velocity);
        } else if (wielded_use_primary_held) {
            // Pull string
            const environment_info = system.ecsu_world.getSingletonMut(fd.EnvironmentInfo).?;
            environment_info.time_multiplier = 0.25;
            var proj_pos = ecs.get_mut(system.ecsu_world.world, proj_ent.id, fd.Position).?;

            proj_pos.z = zm.lerpV(proj_pos.z, -0.8, 0.01);
            weapon_comp.charge = zm.mapLinearV(proj_pos.z, -0.4, -0.8, 0, 1);
        } else {
            // Relax string
            var proj_pos = ecs.get_mut(system.ecsu_world.world, proj_ent.id, fd.Position).?;
            proj_pos.z = zm.lerpV(proj_pos.z, -0.4, 0.1);
        }
    }

    // Arrows
    var builder_proj = ecsu.QueryBuilder.init(system.ecsu_world);
    _ = builder_proj
        .with(fd.PhysicsBody)
        .with(fd.Projectile);

    var filter = builder_proj.buildFilter();
    defer filter.deinit();

    const body_interface = system.physics_world.getBodyInterfaceMut();
    var entity_iter_proj = filter.iterator(struct {
        body: *fd.PhysicsBody,
        proj: *fd.Projectile,
    });

    const up_world_z = zm.f32x4(0.0, 1.0, 0.0, 1.0);
    while (entity_iter_proj.next()) |comps| {
        const velocity = body_interface.getLinearVelocity(comps.body.body_id);
        const velocity_z = zm.loadArr3(velocity);
        if (zm.length3(velocity_z)[0] < 0.01) {
            continue;
        }
        const direction_z = zm.normalize3(velocity_z);
        if (@fabs(direction_z[1]) > 0.99) {
            continue;
        }

        const right_z = zm.normalize3(zm.cross3(direction_z, up_world_z));
        const up_local_z = zm.normalize3(zm.cross3(right_z, direction_z));

        const look_to_z = zm.lookToRh(zm.f32x4(0, 0, 0, 0), direction_z, up_local_z);
        const look_to_jolt_z = zm.transpose(look_to_z);
        const rot_z = zm.matToQuat(look_to_jolt_z);
        var rot: [4]f32 = undefined;
        zm.storeArr4(&rot, rot_z);

        body_interface.setRotation(comps.body.body_id, rot, .dont_activate);

        // trail
        const world_pos = body_interface.getCenterOfMassPosition(comps.body.body_id);
        var fx_ent = system.ecsu_world.newEntity();
        // proj_ent.setName("arrow");
        fx_ent.set(fd.Position{ .x = world_pos[0], .y = world_pos[1], .z = world_pos[2] });
        fx_ent.set(fd.Rotation{});
        fx_ent.set(fd.Scale.createScalar(1));
        fx_ent.set(fd.Transform.init(0, 0, 0));
        fx_ent.set(fd.Forward{});
        fx_ent.set(fd.Dynamic{});
        fx_ent.set(fd.CIShapeMeshInstance{
            .id = IdLocal.id64("sphere"),
            .basecolor_roughness = .{ .r = 1.0, .g = 0.0, .b = 0.0, .roughness = 0.8 },
        });

        const tli_fx = config.events.TimelineInstanceData{
            .ent = fx_ent.id,
            .timeline = IdLocal.init("particle_trail"),
        };

        system.event_manager.triggerEvent(config.events.onAddTimelineInstance_id, &tli_fx);
    }
}

//  ██████╗ █████╗ ██╗     ██╗     ██████╗  █████╗  ██████╗██╗  ██╗███████╗
// ██╔════╝██╔══██╗██║     ██║     ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝
// ██║     ███████║██║     ██║     ██████╔╝███████║██║     █████╔╝ ███████╗
// ██║     ██╔══██║██║     ██║     ██╔══██╗██╔══██║██║     ██╔═██╗ ╚════██║
// ╚██████╗██║  ██║███████╗███████╗██████╔╝██║  ██║╚██████╗██║  ██╗███████║
//  ╚═════╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝

fn onEventFrameCollisions(ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void {
    _ = event_id;
    var system: *SystemState = @ptrCast(@alignCast(ctx));
    const body_interface = system.physics_world.getBodyInterfaceMut();
    const frame_collisions_data = util.castOpaqueConst(config.events.FrameCollisionsData, event_data);

    var arena_state = std.heap.ArenaAllocator.init(system.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var removed_entities = std.ArrayList(ecs.entity_t).initCapacity(arena, 32) catch unreachable;

    // This is in dire need of refactoring...
    for (frame_collisions_data.contacts) |contact| {
        if (!body_interface.isAdded(contact.body_id2)) {
            continue;
        }

        const ent1 = contact.ent1;
        const ent2 = contact.ent2;
        if (std.mem.indexOfScalar(ecs.entity_t, removed_entities.items, ent1) != null) {
            // std.debug.print("fail1 {any}\n", .{ent1});
            continue;
        }
        if (std.mem.indexOfScalar(ecs.entity_t, removed_entities.items, ent2) != null) {
            // std.debug.print("fail2 {any}\n", .{ent2});
            continue;
        }

        const contact_base_offset_z = zm.loadArr4(contact.manifold.base_offset);
        const contact_point1_z = zm.loadArr4(contact.manifold.shape1_relative_contact.points[0]);
        const contact_point_world_z = contact_base_offset_z + contact_point1_z;
        _ = contact_point_world_z;

        if (ent1 != 0 and ecs.has_id(system.ecsu_world.world, ent1, ecs.id(fd.Projectile))) {
            // std.debug.print("proj1 {any} body:{any}\n", .{contact.ent1, contact.body_id1});
            const pos = body_interface.getCenterOfMassPosition(contact.body_id1);
            const velocity = body_interface.getLinearVelocity(contact.body_id1);
            body_interface.removeAndDestroyBody(contact.body_id1);
            ecs.remove(system.ecsu_world.world, ent1, fd.PhysicsBody);
            removed_entities.append(ent1) catch unreachable;

            if (ent2 != 0 and ecs.has_id(system.ecsu_world.world, ent2, ecs.id(fd.Health))) {
                const transform_target = ecs.get(system.ecsu_world.world, ent2, fd.Transform).?;
                const transform_proj = ecs.get(system.ecsu_world.world, ent1, fd.Transform).?;
                // var transform_proj_mat = transform_proj_comp.matrix;
                // var transform_proj_mod_pos = transform_proj_mat[9..];
                // transform_proj_mod_pos[0] = contact_point_world_z[0];
                // transform_proj_mod_pos[1] = contact_point_world_z[1];
                // transform_proj_mod_pos[2] = contact_point_world_z[2];
                const transform_target_z = transform_target.asZM();
                const transform_proj_z = transform_proj.asZM();
                // const transform_proj_z = zm.loadMat43(&transform_proj_mat);
                // const transform_target_z = transform_target.asZM();
                // const transform_proj_z = transform_proj.asZM();
                const transform_target_inv_z = zm.inverse(transform_target_z);
                const mat_z = zm.mul(transform_proj_z, transform_target_inv_z);
                // const pos_z2 = contact_point_world_z;
                const pos_z = zm.util.getTranslationVec(mat_z);
                const rot_z = zm.matToQuat(mat_z);
                var pos_proj = ecs.get_mut(system.ecsu_world.world, ent1, fd.Position).?;
                var rot_proj = ecs.get_mut(system.ecsu_world.world, ent1, fd.Rotation).?;
                pos_proj.fromZM(pos_z);
                rot_proj.fromZM(rot_z);

                ecs.add_id(system.ecsu_world.world, ent1, system.ecsu_world.pair(ecs.ChildOf, ent2));

                var health2 = ecs.get_mut(system.ecsu_world.world, ent2, fd.Health).?;
                if (health2.value > 0) {
                    health2.value -= 50;
                    if (health2.value <= 0) {
                        body_interface.setMotionType(contact.body_id2, .dynamic, .activate);
                        body_interface.addImpulseAtPosition(
                            contact.body_id2,
                            .{
                                velocity[0] * 10,
                                velocity[1] * 0,
                                velocity[2] * 10,
                            },
                            pos,
                        );
                        ecs.remove(system.ecsu_world.world, ent2, fd.FSM);
                        removed_entities.append(ent2) catch unreachable;
                        body_interface.addImpulse(
                            contact.body_id2,
                            .{ 0, 100, 0 },
                        );
                    }
                    // std.debug.print("lol2 {any}\n", .{ent2.id});
                }
            }
        }

        if (contact.ent2 != 0 and ecs.has_id(system.ecsu_world.world, ent2, ecs.id(fd.Projectile))) {
            // std.debug.print("proj2 {any} body:{any}\n", .{contact.ent2, contact.body_id2});
            const pos = body_interface.getCenterOfMassPosition(contact.body_id2);
            const velocity = body_interface.getLinearVelocity(contact.body_id2);
            body_interface.removeAndDestroyBody(contact.body_id2);
            ecs.remove(system.ecsu_world.world, ent2, fd.PhysicsBody);
            removed_entities.append(ent2) catch unreachable;

            if (contact.ent1 != 0 and ecs.has_id(system.ecsu_world.world, ent1, ecs.id(fd.Health))) {
                // var pos_target = ecs.get(system.ecsu_world.world, ent1, fd.Position).?;
                // _ = pos_target;
                const transform_target = ecs.get(system.ecsu_world.world, ent2, fd.Transform).?;
                const transform_proj = ecs.get(system.ecsu_world.world, ent1, fd.Transform).?;
                // var transform_proj_mat = transform_proj_comp.matrix;
                // var transform_proj_mod_pos = transform_proj_mat[9..];
                // transform_proj_mod_pos[0] = contact_point_world_z[0];
                // transform_proj_mod_pos[1] = contact_point_world_z[1];
                // transform_proj_mod_pos[2] = contact_point_world_z[2];
                const transform_target_z = transform_target.asZM();
                const transform_proj_z = transform_proj.asZM();
                // const transform_proj_z = zm.loadMat43(&transform_proj_mat);
                const transform_target_inv_z = zm.inverse(transform_target_z);
                const mat_z = zm.mul(transform_proj_z, transform_target_inv_z);
                // const pos_z = contact_point_world_z;
                const pos_z = zm.util.getTranslationVec(mat_z);
                const rot_z = zm.matToQuat(mat_z);
                var pos_proj = ecs.get_mut(system.ecsu_world.world, ent2, fd.Position).?;
                var rot_proj = ecs.get_mut(system.ecsu_world.world, ent2, fd.Rotation).?;
                pos_proj.fromZM(pos_z);
                rot_proj.fromZM(rot_z);
                ecs.add_id(system.ecsu_world.world, ent2, system.ecsu_world.pair(ecs.ChildOf, ent1));

                var health1 = ecs.get_mut(system.ecsu_world.world, ent1, fd.Health).?;
                if (health1.value > 0) {
                    health1.value -= 50;
                    if (health1.value <= 0) {
                        body_interface.setMotionType(contact.body_id1, .dynamic, .activate);
                        body_interface.addImpulseAtPosition(
                            contact.body_id1,
                            .{
                                velocity[0] * 10,
                                velocity[1] * 0,
                                velocity[2] * 10,
                            },
                            pos,
                        );
                        ecs.remove(system.ecsu_world.world, ent1, fd.FSM);
                        removed_entities.append(ent1) catch unreachable;
                        body_interface.addImpulse(
                            contact.body_id1,
                            .{ 0, 100, 0 },
                        );
                    }
                    // std.debug.print("lol1 {any}\n", .{health1.value});
                }
            }
        }
    }
}
