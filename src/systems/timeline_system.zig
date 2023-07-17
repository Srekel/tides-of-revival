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

pub const EventFunc = fn (entity: ecs.entity_t, data: *anyopaque) void;

pub const TimelineEvent = struct {
    trigger_time: f32,
    trigger_id: IdLocal,
    func: *const EventFunc,
    data: *anyopaque,
};

pub const LoopBehavior = enum {
    remove,
    // remove_entity,
    loop_from_zero,
    loop_no_time_loss,
    // ping_pong,
};

pub const Timeline = struct {
    id: IdLocal,
    events: std.ArrayList(TimelineEvent), // sorted by time
    // curves: ...
    loop_behavior: LoopBehavior,
    instances: std.ArrayList(Instance),
    duration: f32 = 0,
};

pub const Instance = struct {
    time_start: f32,
    time_end: f32 = 0,
    entity: ecs.entity_t = 0,
    upcoming_event_index: u32 = 0,
};

const SystemState = struct {
    flecs_sys: ecs.entity_t,
    allocator: std.mem.Allocator,
    physics_world: *zphy.PhysicsSystem,
    ecs_world: *ecs.world_t,
    frame_data: *input.FrameData,

    timelines: std.ArrayList(Timeline),
};

pub fn create(name: IdLocal, ctx: util.Context) !*SystemState {
    const allocator = ctx.getConst(config.allocator.hash, std.mem.Allocator).*;
    const ecs_world = ctx.get(config.ecs_world.hash, ecs.world_t);
    const physics_world = ctx.get(config.physics_world.hash, zphy.PhysicsSystem);
    const frame_data = ctx.get(config.input_frame_data.hash, input.FrameData);
    const event_manager = ctx.get(config.event_manager.hash, EventManager);

    var system = allocator.create(SystemState) catch unreachable;
    var flecs_sys = ecs_world.newWrappedRunSystem(name.toCString(), .on_update, fd.NOCOMP, update, .{ .ctx = system });
    system.* = .{
        .flecs_sys = flecs_sys,
        .allocator = allocator,
        .ecs_world = ecs_world,
        .physics_world = physics_world,
        .frame_data = frame_data,
        .timelines = std.ArrayList(Timeline).initCapacity(allocator, 16) catch unreachable,
    };

    event_manager.registerListener(config.events.onRegisterTimeline_id, onRegisterTimeline, system);
    event_manager.registerListener(config.events.onAddTimelineInstance_id, onAddTimelineInstance, system);

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.allocator.destroy(system);
}

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    updateTimelines(system, iter.iter.delta_time);
}

fn updateTimelines(system: *SystemState, dt: f32) void {
    _ = dt;
    const environment_info = system.ecs_world.getSingleton(fd.EnvironmentInfo).?;
    const time_now = environment_info.world_time;

    for (system.timelines.items) |timeline| {
        const events = timeline.events;

        for (timeline.instances.items) |*instance| {
            const time_curr = time_now - instance.time_start;
            while (instance.upcoming_event_index < events.items.len) {
                const event = events.items[instance.upcoming_event_index];
                if (event.trigger_time <= time_curr) {
                    event.func(instance.entity, event.data);
                    instance.upcoming_event_index += 1;
                } else {
                    break;
                }
            }

            if (time_curr >= instance.time_end) {
                switch (timeline.loop_behavior) {
                    .remove => {
                        // TODO
                    },
                    .loop_from_zero => {
                        instance.time_start = time_now;
                        instance.upcoming_event_index = 0;
                    },
                    .loop_no_time_loss => {
                        instance.time_start += timeline.duration;
                        instance.upcoming_event_index = 0;
                    },
                }
            }
        }
    }
}

fn onRegisterTimeline(ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void {
    _ = event_id;
    var system: *SystemState = @ptrCast(@alignCast(ctx));
    const timeline_template_data = util.castOpaqueConst(config.events.TimelineTemplateData, event_data);
    var timeline = Timeline{
        .id = timeline_template_data.id,
        .instances = std.ArrayList(Instance).init(system.allocator),
        .events = std.ArrayList(TimelineEvent).init(system.allocator),
        .loop_behavior = timeline_template_data.loop_behavior,
    };
    timeline.events.appendSlice(timeline_template_data.events) catch unreachable;
    timeline.duration = timeline.events.getLast().trigger_time;
    system.timelines.append(timeline) catch unreachable;
}

fn onAddTimelineInstance(ctx: *anyopaque, event_id: u64, event_data: *const anyopaque) void {
    _ = event_id;
    var system: *SystemState = @ptrCast(@alignCast(ctx));
    const timeline_instance_data = util.castOpaqueConst(config.events.TimelineInstanceData, event_data);
    for (system.timelines.items) |*timeline| {
        if (timeline.id.eql(timeline_instance_data.timeline)) {
            const environment_info = system.ecs_world.getSingleton(fd.EnvironmentInfo).?;
            const time_now = environment_info.world_time;
            timeline.instances.append(.{
                .time_start = time_now,
                .time_end = time_now + timeline.duration,
                // .ent = 0,
            }) catch unreachable;
        }
    }
    // const timeline = @ptrCast(*Timeline, @alignCast(@alignOf(Timeline), event_data));
    // system.timelines.append(timeline.*);
}
