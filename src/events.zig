const zphy = @import("zphysics");
const flecs = @import("flecs");
const IdLocal = @import("variant.zig").IdLocal;
const timeline_system = @import("systems/timeline_system.zig");

// FrameCollisions
pub const frame_collisions_id = IdLocal.init("frame_collisions");
pub const CollisionContact = struct {
    body_id1: u32,
    body_id2: u32,
    ent1: flecs.EntityId,
    ent2: flecs.EntityId,
    manifold: zphy.ContactManifold,
    settings: zphy.ContactSettings,
};
pub const FrameCollisionsData = struct {
    contacts: []CollisionContact,
};

// pub const OnCollision = struct {};
// pub fn onCollisionEvent(world: *flecs.c.EcsWorld) flecs.Event {
//     return @intToEnum(flecs.Event, flecs.meta.componentId(world, OnCollision));
// }
// pub fn onCollisionId(world: *flecs.c.EcsWorld) flecs.EcsId {
//     return flecs.meta.componentId(world, OnCollision);
// }

// Timeline template
// (Not sure if this should be an event or a component)
pub const onRegisterTimeline_id = IdLocal.init("register_timeline");
pub const TimelineTemplateData = struct {
    id: IdLocal,
    events: []timeline_system.TimelineEvent,
    loop_behavior: timeline_system.LoopBehavior,
};

// Timeline instance
// (Not sure if this should be an event or a component)
pub const onAddTimelineInstance_id = IdLocal.init("timeline_instance");
pub const TimelineInstanceData = struct {
    ent: flecs.EntityId,
    timeline: IdLocal,
};
