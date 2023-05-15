const zphy = @import("zphysics");
const flecs = @import("flecs");
const IdLocal = @import("variant.zig").IdLocal;

// OnCollision
pub const OnCollision = struct {};
pub fn onCollisionId(world: *flecs.c.EcsWorld) flecs.EntityId {
    return flecs.meta.componentId(world, OnCollision);
}
pub const OnCollisionContext = struct {
    body1: u64,
    boyd2: u64,
    ent1: flecs.EntityId,
    ent2: flecs.EntityId,
};
