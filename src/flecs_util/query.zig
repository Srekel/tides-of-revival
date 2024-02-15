const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util.zig");

pub const Query = struct {
    world: *ecs.world_t,
    query: *ecs.query_t,

    pub fn init(world: *ecs.world_t, desc: *ecs.query_desc_t) @This() {
        return .{
            .world = world,
            .query = ecs.query_init(world, desc) catch unreachable,
        };
    }

    pub fn deinit(self: *@This()) void {
        ecs.query_fini(self.query);
    }

    pub fn asString(self: *@This()) [*c]u8 {
        const filter = ecs.query_get_filter(self.query);
        return ecs.filter_str(self.world, filter);
    }

    pub fn changed(self: *@This(), iter: ?*ecs.iter_t) bool {
        if (iter) |it| return ecs.query_changed(self.query, it);
        return ecs.query_changed(self.query, null);
    }

    /// gets an iterator that let you iterate the tables and then it provides an inner iterator to interate entities
    pub fn tableIterator(self: *@This(), comptime Components: type) ecsu.TableIterator(Components) {
        temp_iter_storage = ecs.query_iter(self.world, self.query);
        return ecsu.TableIterator(Components).init(&temp_iter_storage, ecs.query_next);
    }

    // storage for the iterator so it can be passed by reference. Do not in-flight two Queries at once!
    var temp_iter_storage: ecs.iter_t = undefined;

    /// gets an iterator that iterates all matched entities from all tables in one iteration. Do not create more than one at a time!
    pub fn iterator(self: *@This(), comptime Components: type) ecsu.Iterator(Components) {
        temp_iter_storage = ecs.query_iter(self.world, self.query);
        return ecsu.Iterator(Components).init(&temp_iter_storage, ecs.query_next);
    }

    /// allows either a function that takes 1 parameter (a struct with fields that match the components in the query) or multiple paramters
    /// (each param should match the components in the query in order)
    pub fn each(self: *@This(), comptime function: anytype) void {
        // dont allow BoundFn
        std.debug.assert(@typeInfo(@TypeOf(function)) == .Fn);
        const arg_count = comptime ecsu.meta.argCount(function);

        if (arg_count == 1) {
            const Components = @typeInfo(@TypeOf(function)).Fn.args[0].arg_type.?;

            var iter = self.iterator(Components);
            while (iter.next()) |comps| {
                @call(.{ .modifier = .always_inline }, function, .{comps});
            }
        } else {
            const Components = std.meta.ArgsTuple(@TypeOf(function));

            var iter = self.iterator(Components);
            while (iter.next()) |comps| {
                @call(.{ .modifier = .always_inline }, function, ecsu.meta.fieldsTuple(comps));
            }
        }
    }
};
