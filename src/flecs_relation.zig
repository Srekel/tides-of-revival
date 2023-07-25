const ecs = @import("zflecs");
const ecsu = @import("flecs_util/flecs_util.zig");

pub fn registerRelations(ecsu_world: ecsu.World) void {
    Hometown = ecsu_world.newEntityWithName("HomeTown").id;
    // Hometown = ecsu_world.newEntity();
    // Hometown.set(RelHometown);
}

pub var Hometown: ecs.entity_t = 0;

// const RelHometown = struct {};
// const RelWeaponProjectileInChamber = struct {};
