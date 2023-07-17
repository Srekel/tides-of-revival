const std = @import("std");
const ecs = @import("zflecs");

pub const Type = struct {
    world: *ecs.world_t,
    type: ecs.type_t,

    pub fn init(world: *ecs.world_t, t: ecs.type_t) Type {
        return .{ .world = world, .type = t.? };
    }

    /// returns the number of component ids in the type
    pub fn count(self: Type) usize {
        return @intCast(ecs.vector_count(self.type.?));
    }

    /// returns the formatted list of components in the type
    pub fn asString(self: Type) []const u8 {
        const str = ecs.type_str(self.world, self.type);
        const len = std.mem.len(str);
        return str[0..len];
    }

    /// returns an array of component ids
    pub fn toArray(self: Type) []const ecs.entity_t {
        return @as([*c]const ecs.entity_t, @ptrCast(@alignCast(flecs.c._ecs_vector_first(self.type, @sizeOf(u64), @alignOf(u64)))))[1 .. self.count() + 1];
    }
};
