const std = @import("std");
const input = @import("../input.zig");
const ID = @import("../core/core.zig").ID;
const ecsu = @import("../flecs_util/flecs_util.zig");
const zphy = @import("zphysics");
const EventManager = @import("../core/event_manager.zig").EventManager;
const prefab_manager = @import("../prefab_manager.zig");
const timeline_system = @import("../systems/timeline_system.zig");
const ecs = @import("zflecs");
const core = @import("../core/core.zig");
const config = @import("config.zig");
const util = @import("../util.zig");
const fd = @import("flecs_data.zig");
const zm = @import("zmath");

pub const WaveSpawnContext = struct {
    ecsu_world: ecsu.World,
    physics_world: *zphy.PhysicsSystem,
    prefab_mgr: *prefab_manager.PrefabManager,
    event_mgr: *EventManager,
    timeline_system: *timeline_system.SystemUpdateContext,
    root_ent: ?ecs.entity_t,
    speed: f32 = 1,
    stage: f32 = 0,
};

fn spawnGiantAnt(entity: ecs.entity_t, data: *anyopaque) void {
    _ = entity;

    var ctx = util.castOpaque(WaveSpawnContext, data);
    // TODO(gmodarelli): Restore game-over state
    // if (ctx.gfx.end_screen_accumulated_time > 0) {
    //     return;
    // }

    ctx.stage = 2;
    // timeline_system.modifyInstanceSpeed(ctx.timeline_system, ID("giantAntSpawn").hash, 0, ctx.speed);
    const root_pos = ecs.get(ctx.ecsu_world.world, ctx.root_ent.?, fd.Position).?;

    var capsule_rot = [_]f32{ 1, 0, 0, 0 };
    const capsule_rot_z = zm.quatFromRollPitchYaw(std.math.pi / 2.0, 0, 0);
    zm.storeArr4(&capsule_rot, capsule_rot_z);

    const group_angle = std.crypto.random.float(f32) * std.math.tau;
    const to_spawn = 0 + @divFloor(ctx.stage, 2);
    std.log.info("stage {} to_spawn {}\n", .{ ctx.stage, to_spawn });
    for (0..@intFromFloat(to_spawn)) |i_giant_ant| {
        const individual_angle: f32 = 2 * std.math.pi * @as(f32, @floatFromInt(i_giant_ant)) / to_spawn;
        var ent = ctx.prefab_mgr.instantiatePrefab(ctx.ecsu_world, config.prefab.slime);
        const spawn_pos = [3]f32{
            root_pos.x + (60 + to_spawn * 2) * std.math.sin(group_angle) + (5 + to_spawn * 1) * std.math.sin(individual_angle),
            root_pos.y + 20,
            root_pos.z + (60 + to_spawn * 2) * std.math.cos(group_angle) + (5 + to_spawn * 1) * std.math.cos(individual_angle),
        };

        if (root_pos.x < 0 or root_pos.x >= config.world_size_x or root_pos.z < 0 or root_pos.z >= config.world_size_z) {
            break;
        }

        ent.set(fd.Position{
            .x = spawn_pos[0],
            .y = spawn_pos[1],
            .z = spawn_pos[2],
        });

        const is_boss = ctx.stage > 7 and std.crypto.random.float(f32) > 0.97;
        const is_big = ctx.stage > 2 and !is_boss and std.crypto.random.float(f32) > 0.9;

        const scale: f32 = if (is_boss) 2.5 else if (is_big) 1.1 else 2.7;
        ent.set(fd.Scale.createScalar(scale));

        const hp = blk: {
            if (is_boss) {
                break :blk 100000 + ctx.stage * 1000 + ctx.stage * ctx.stage * 250;
            } else if (is_big) {
                break :blk 10000 + ctx.stage * 1000;
            } else {
                break :blk 1;
            }
        };
        ent.set(fd.Health{ .value = hp });
        ent.addPair(fd.FSM_ENEMY, fd.FSM_ENEMY_Idle);

        // ent.set(fd.CIFSM{ .state_machine_hash = core.IdLocal.id64("giant_ant") });

        const body_interface = ctx.physics_world.getBodyInterfaceMut();

        const capsule_shape_settings = zphy.SphereShapeSettings.create(0.5 * scale) catch unreachable;
        defer capsule_shape_settings.release();

        const root_shape_settings = zphy.DecoratedShapeSettings.createRotatedTranslated(
            &capsule_shape_settings.asShapeSettings().*,
            capsule_rot,
            .{ 0, 0, 0 },
        ) catch unreachable;
        defer root_shape_settings.release();
        const root_shape = root_shape_settings.createShape() catch unreachable;

        const body_id = body_interface.createAndAddBody(.{
            .position = .{ spawn_pos[0], spawn_pos[1], spawn_pos[2], 0 },
            .rotation = .{ 0, 0, 0, 1 },
            .shape = root_shape,
            .motion_type = .kinematic,
            .object_layer = config.physics.object_layers.moving,
            .motion_quality = .discrete,
            .user_data = ent.id,
            .angular_damping = 0.975,
            .inertia_multiplier = 10,
            .friction = 0.5,
        }, .activate) catch unreachable;

        if (is_boss) {
            std.log.info("ANT boss hp: {d:5.2}", .{hp});
            ent.set(fd.PointLight{
                .color = .{ .r = 1, .g = 0.15, .b = 0.15 },
                .range = 20.0,
                .intensity = 8.0,
            });
        } else if (is_big) {
            std.log.info("ANT big  hp: {d:5.2}", .{hp});
            ent.set(fd.PointLight{
                .color = .{ .r = 1, .g = 0.45, .b = 0.2 },
                .range = 8.0,
                .intensity = 6.0,
            });
        } else {
            ent.set(fd.PointLight{
                .color = .{ .r = 0.2, .g = 0.2, .b = 0.9 },
                .range = 6.0,
                .intensity = 5.0,
            });
        }
        // Assign to flecs component
        ent.set(fd.PhysicsBody{ .body_id = body_id, .shape_opt = root_shape });

        ent.add(fd.SettlementEnemy);
    }
}

pub fn initTimelines(tl_giant_ant_spawn_ctx: *WaveSpawnContext) void {
    const tl_giant_ant_spawn = config.events.TimelineTemplateData{
        .id = ID("giantAntSpawn"),
        .events = &[_]timeline_system.TimelineEvent{
            .{
                .trigger_time = 150,
                .trigger_id = ID("onSpawnAroundPlayer"),
                .func = spawnGiantAnt,
                .data = tl_giant_ant_spawn_ctx,
            },
        },
        .curves = &.{},
        .loop_behavior = .loop_no_time_loss,
    };
    _ = tl_giant_ant_spawn; // autofix

    const tli_giant_ant_spawn = config.events.TimelineInstanceData{
        .ent = 0,
        .start_time = 2,
        .timeline = ID("giantAntSpawn"),
    };
    _ = tli_giant_ant_spawn; // autofix

    // tl_giant_ant_spawn_ctx.event_mgr.triggerEvent(config.events.onRegisterTimeline_id, &tl_giant_ant_spawn);
    // tl_giant_ant_spawn_ctx.event_mgr.triggerEvent(config.events.onAddTimelineInstance_id, &tli_giant_ant_spawn);

    const tl_particle_trail = config.events.TimelineTemplateData{
        .id = ID("particle_trail"),
        .events = &.{},
        .curves = &[_]timeline_system.Curve{
            .{
                .id = .{}, // ID("scale"),
                .points = &[_]timeline_system.CurvePoint{
                    .{ .time = 0, .value = 0.000 },
                    .{ .time = 0.1, .value = 0.01 },
                    .{ .time = 0.35, .value = 0.004 },
                    .{ .time = 0.5, .value = 0 },
                },
            },
        },
        .loop_behavior = .remove_entity,
    };
    tl_giant_ant_spawn_ctx.event_mgr.triggerEvent(config.events.onRegisterTimeline_id, &tl_particle_trail);

    const tl_despawn = config.events.TimelineTemplateData{
        .id = ID("despawn"),
        .events = &.{},
        .curves = &[_]timeline_system.Curve{
            .{
                .id = ID("ignore"), // ID("scale"),
                .points = &[_]timeline_system.CurvePoint{
                    .{ .time = 150, .value = 1 },
                },
            },
        },
        .loop_behavior = .remove_entity,
    };
    tl_giant_ant_spawn_ctx.event_mgr.triggerEvent(config.events.onRegisterTimeline_id, &tl_despawn);
}
