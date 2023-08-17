const zphy = @import("zphysics");
const ecs = @import("zflecs");
const IdLocal = @import("variant.zig").IdLocal;
const timeline_system = @import("systems/timeline_system.zig");

// FrameCollisions
pub const frame_collisions_id = IdLocal.init("frame_collisions");
pub const CollisionContact = struct {
    body_id1: u32,
    body_id2: u32,
    ent1: ecs.entity_t,
    ent2: ecs.entity_t,
    manifold: zphy.ContactManifold,
    settings: zphy.ContactSettings,
};
pub const FrameCollisionsData = struct {
    contacts: []CollisionContact,
};

// Timeline template
// (Not sure if this should be an event or a component)
pub const onRegisterTimeline_id = IdLocal.init("register_timeline");
pub const TimelineTemplateData = struct {
    id: IdLocal,
    events: []const timeline_system.TimelineEvent,
    curves: []const timeline_system.Curve,
    loop_behavior: timeline_system.LoopBehavior,
};

// Timeline instance
// (Not sure if this should be an event or a component)
pub const onAddTimelineInstance_id = IdLocal.init("timeline_instance");
pub const TimelineInstanceData = struct {
    ent: ecs.entity_t,
    timeline: IdLocal,
};
