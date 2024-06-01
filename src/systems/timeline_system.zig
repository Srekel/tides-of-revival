const std = @import("std");
const math = std.math;
const ecs = @import("zflecs");
const zm = @import("zmath");
const zphy = @import("zphysics");
const ztracy = @import("ztracy");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const fr = @import("../config/flecs_relation.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");
const config = @import("../config/config.zig");
const input = @import("../input.zig");
const EventManager = @import("../core/event_manager.zig").EventManager;

pub const EventFunc = fn (ent: ecs.entity_t, data: *anyopaque) void;

pub const CurvePoint = struct {
    time: f32 = 0,
    value: f32 = 0,
};

pub const TimelineEvent = struct {
    trigger_time: f32,
    trigger_id: IdLocal,
    func: *const EventFunc,
    data: *anyopaque,
};

pub const LoopBehavior = enum {
    remove_instance,
    remove_entity,
    loop_from_zero,
    loop_no_time_loss,
    // ping_pong,
};

pub const Curve = struct {
    id: IdLocal,
    points: []const CurvePoint,
};

pub const Timeline = struct {
    id: IdLocal,
    events: std.ArrayList(TimelineEvent), // sorted by time
    curves: std.ArrayList(Curve),
    loop_behavior: LoopBehavior,
    instances: std.ArrayList(Instance),
    instances_to_add: std.ArrayList(Instance),
    duration: f32 = 0,
};

pub const Instance = struct {
    time_start: f32,
    ent: ecs.entity_t = 0,
    upcoming_event_index: u32 = 0,
    speed: f32 = 1,
};

pub const SystemState = struct {
    flecs_sys: ecs.entity_t,
    allocator: std.mem.Allocator,
    physics_world: *zphy.PhysicsSystem,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,

    timelines: std.ArrayList(Timeline),
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const ecsu_world = ctx.get(config.ecsu_world.hash, ecsu.World).*;
    const physics_world = ctx.get(config.physics_world.hash, zphy.PhysicsSystem);
    const input_frame_data = ctx.get(config.input_frame_data.hash, input.FrameData);
    const event_mgr = ctx.get(config.event_mgr.hash, EventManager);

    const system = allocator.create(SystemState) catch unreachable;
    const flecs_sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.OnUpdate, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .physics_world = physics_world,
        .input_frame_data = input_frame_data,
        .timelines = std.ArrayList(Timeline).initCapacity(allocator, 16) catch unreachable,
    };

    event_mgr.registerListener(config.events.onRegisterTimeline_id, onRegisterTimeline, system);
    event_mgr.registerListener(config.events.onAddTimelineInstance_id, onAddTimelineInstance, system);

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Timeline System: Update", 0x00_ff_00_ff);
    defer trazy_zone.End();

    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    updateTimelines(system, iter.iter.delta_time);
}

fn updateTimelines(system: *SystemState, dt: f32) void {
    _ = dt;
    const environment_info = system.ecsu_world.getSingleton(fd.EnvironmentInfo).?;
    const world_time = environment_info.world_time;

    for (system.timelines.items) |*timeline| {
        // const events = timeline.events;

        if (timeline.instances.items.len == 0 and timeline.instances_to_add.items.len == 0) {
            continue;
        }

        timeline.instances.appendSlice(timeline.instances_to_add.items) catch unreachable;
        timeline.instances_to_add.clearRetainingCapacity();
    }

    for (system.timelines.items) |*timeline| {
        const events = timeline.events;

        if (timeline.instances.items.len == 0 and timeline.instances_to_add.items.len == 0) {
            continue;
        }

        var instances_to_remove = std.ArrayList(usize).init(system.allocator);

        for (timeline.curves.items) |curve| {
            switch (curve.id.hash) {
                0 => {
                    for (timeline.instances.items) |*instance| {
                        const speed = instance.speed;
                        const time_into = world_time - instance.time_start;
                        const time_curr = time_into * speed;
                        const ent = instance.ent;
                        for (curve.points[0 .. curve.points.len - 1], 0..) |cp, i| {
                            const cp_next = curve.points[i + 1];
                            if (cp_next.time < time_curr) {
                                continue;
                            }

                            const cp_duration = cp_next.time - cp.time;
                            const cp_progress = (time_curr - cp.time) / cp_duration;
                            const value = std.math.lerp(cp.value, cp_next.value, cp_progress);

                            var scale = ecs.get_mut(system.ecsu_world.world, ent, fd.Scale).?;
                            scale.x = value;
                            scale.y = value;
                            scale.z = value;
                            break;
                        }
                    }
                },
                1 => {
                    for (timeline.instances.items) |*instance| {
                        const speed = instance.speed;
                        const time_into = world_time - instance.time_start;
                        const time_curr = time_into * speed;
                        const ent = instance.ent;
                        for (curve.points[0 .. curve.points.len - 1], 0..) |cp, i| {
                            const cp_next = curve.points[i + 1];
                            if (cp_next.time < time_curr) {
                                continue;
                            }

                            const cp_duration = cp_next.time - cp.time;
                            const cp_progress = (time_curr - cp.time) / cp_duration;
                            const value = std.math.lerp(cp.value, cp_next.value, cp_progress);

                            var rotation = ecs.get_mut(system.ecsu_world.world, ent, fd.Rotation).?;
                            const new_rotation = fd.Rotation.initFromEulerDegrees(0.0, value, 0.0);
                            rotation.x = new_rotation.x;
                            rotation.y = new_rotation.y;
                            rotation.z = new_rotation.z;
                            rotation.w = new_rotation.w;
                            break;
                        }
                    }
                },
                else => {},
            }
        }

        for (timeline.instances.items, 0..) |*instance, i| {
            const speed = instance.speed;
            const time_into = world_time - instance.time_start;
            const time_curr = time_into * speed;

            while (instance.upcoming_event_index < events.items.len) {
                const event = events.items[instance.upcoming_event_index];
                if (event.trigger_time <= time_curr) {
                    event.func(instance.ent, event.data);
                    instance.upcoming_event_index += 1;
                } else {
                    break;
                }
            }

            if (time_curr >= timeline.duration) {
                switch (timeline.loop_behavior) {
                    .remove_instance => {
                        instances_to_remove.append(i) catch unreachable;
                    },
                    .remove_entity => {
                        if (system.ecsu_world.isAlive(instance.ent)) {
                            system.ecsu_world.delete(instance.ent);
                        }
                        instances_to_remove.append(i) catch unreachable;
                    },
                    .loop_from_zero => {
                        instance.time_start = world_time;
                        instance.upcoming_event_index = 0;
                    },
                    .loop_no_time_loss => {
                        instance.time_start += timeline.duration / speed;
                        instance.upcoming_event_index = 0;
                    },
                }
            }
        }

        var it = std.mem.reverseIterator(instances_to_remove.items);
        while (it.next()) |index| {
            _ = timeline.instances.swapRemove(index);
        }
    }
}
//  █████╗ ██████╗ ██╗
// ██╔══██╗██╔══██╗██║
// ███████║██████╔╝██║
// ██╔══██║██╔═══╝ ██║
// ██║  ██║██║     ██║
// ╚═╝  ╚═╝╚═╝     ╚═╝

pub fn modifyInstanceSpeed(self: *SystemState, timeline_id_hash: u64, ent: ecs.entity_t, speed: f32) void {
    for (self.timelines.items) |*timeline| {
        if (timeline.id.hash != timeline_id_hash) {
            continue;
        }

        for (timeline.instances.items) |*instance| {
            if (instance.ent == ent) {
                instance.speed = speed;
                return;
            }
        }

        for (timeline.instances_to_add.items) |*instance| {
            if (instance.ent == ent) {
                instance.speed = speed;
                return;
            }
        }
    }
    unreachable;
}

// ███████╗██╗   ██╗███████╗███╗   ██╗████████╗███████╗
// ██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝██╔════╝
// █████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║   ███████╗
// ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║   ╚════██║
// ███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║   ███████║
// ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝

fn onRegisterTimeline(ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void {
    _ = event_id;
    var system: *SystemState = @ptrCast(@alignCast(ctx));
    const timeline_template_data = util.castOpaqueConst(config.events.TimelineTemplateData, event_data);
    var timeline = Timeline{
        .id = timeline_template_data.id,
        .instances = std.ArrayList(Instance).init(system.allocator),
        .instances_to_add = std.ArrayList(Instance).init(system.allocator),
        .events = std.ArrayList(TimelineEvent).init(system.allocator),
        .curves = std.ArrayList(Curve).init(system.allocator),
        .loop_behavior = timeline_template_data.loop_behavior,
    };
    timeline.events.appendSlice(timeline_template_data.events) catch unreachable;
    timeline.curves.appendSlice(timeline_template_data.curves) catch unreachable;
    if (timeline.events.items.len > 0) {
        timeline.duration = timeline.events.getLast().trigger_time;
    }
    if (timeline.curves.items.len > 0) {
        for (timeline.curves.items) |curve| {
            timeline.duration = @max(timeline.duration, curve.points[curve.points.len - 1].time);
        }
    }
    system.timelines.append(timeline) catch unreachable;
}

fn onAddTimelineInstance(ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void {
    _ = event_id;
    var system: *SystemState = @ptrCast(@alignCast(ctx));
    const timeline_instance_data = util.castOpaqueConst(config.events.TimelineInstanceData, event_data);
    for (system.timelines.items) |*timeline| {
        if (timeline.id.eql(timeline_instance_data.timeline)) {
            const environment_info = system.ecsu_world.getSingleton(fd.EnvironmentInfo).?;
            const world_time = environment_info.world_time;
            timeline.instances_to_add.append(.{
                .time_start = world_time - timeline_instance_data.start_time,
                .ent = timeline_instance_data.ent,
            }) catch unreachable;

            break;
        }
    }
    // const timeline = @ptrCast(*Timeline, @alignCast(@alignOf(Timeline), event_data));
    // system.timelines.append(timeline.*);
}
