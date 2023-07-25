const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_utils.zig");

/// void {} is an allowed T for Terms that iterate only the entities. Void is requiried when using initWithPair
pub fn Term(comptime T: anytype) type {
    std.debug.assert(@TypeOf(T) == type or @TypeOf(T) == void);

    return struct {
        const Self = @This();

        world: ecsu.World,
        term: ecs.term_t,

        const Iterator = struct {
            iter: ecs.iter_t,
            index: usize = 0,

            pub fn init(iter: ecs.iter_t) Iterator {
                return .{ .iter = iter };
            }

            pub fn next(self: *Iterator) ?*T {
                if (self.index >= self.iter.count) {
                    self.index = 0;
                    if (!ecs.term_next(&self.iter)) return null;
                }

                self.index += 1;
                const array = ecsu.column(&self.iter, T, 1);
                return &array[self.index - 1];
            }

            pub fn entity(self: *Iterator) ecs.entity_t {
                return self.iter.entities[self.index - 1];
            }
        };

        const EntityIterator = struct {
            iter: ecs.iter_t,
            index: usize = 0,

            pub fn init(iter: ecs.iter_t) EntityIterator {
                return .{ .iter = iter };
            }

            pub fn next(self: *EntityIterator) ?ecs.entity_t {
                if (self.index >= self.iter.count) {
                    self.index = 0;
                    if (!ecs.term_next(&self.iter)) return null;
                }

                self.index += 1;
                return self.iter.entities[self.index - 1];
            }
        };

        pub fn init(world: ecsu.World) Self {
            var term = std.mem.zeroInit(ecs.term_t, .{ .id = world.componentId(T) });
            return .{ .world = world, .term = term };
        }

        pub fn initWithPair(world: ecsu.World, pair: ecs.entity_t) Self {
            var term = std.mem.zeroInit(ecs.term_t, .{ .id = pair });
            return .{ .world = world, .term = term };
        }

        pub fn deinit(self: *Self) void {
            ecs.term_fini(&self.term);
        }

        // only export each if we have an actualy type T
        pub usingnamespace if (@TypeOf(T) == type) struct {
            pub fn iterator(self: *Self) Iterator {
                return Iterator.init(ecs.term_iter(self.world.world, &self.term));
            }

            pub fn each(self: *Self, function: fn (ecs.entity_t, *T) void) void {
                var iter = self.iterator();
                while (iter.next()) |comp| {
                    function(iter.entity(), comp);
                }
            }
        } else struct {
            pub fn iterator(self: *Self) EntityIterator {
                return EntityIterator.init(ecs.term_iter(self.world.world, &self.term));
            }
        };

        pub fn entityIterator(self: *Self) EntityIterator {
            return EntityIterator.init(ecs.term_iter(self.world.world, &self.term));
        }
    };
}
