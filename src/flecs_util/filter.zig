const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util.zig");

pub const Filter = struct {
    world: *ecs.world_t,
    filter: *ecs.Filter = undefined,

    /// filter iterator that lets you fetch components via get/getOpt
    /// TODO: is this thing necessary? Seems the other iterators are more then capable compared to this thing.
    const FilterIterator = struct {
        iter: ecs.iter_t,
        index: usize = 0,

        pub fn init(iter: ecs.iter_t) @This() {
            return .{ .iter = iter };
        }

        pub fn next(self: *@This()) ?void {
            if (self.index >= self.iter.count) {
                self.index = 0;
                if (!ecs.ecs_filter_next(&self.iter)) return null;
            }

            self.index += 1;
        }

        pub fn entity(self: *@This()) ecs.entity_t {
            return self.iter.entities[self.index - 1];
        }

        /// gets the index into the terms array of this type
        fn getTermIndex(self: @This(), comptime T: type) usize {
            // const comp_id = ecsu.meta.componentHandle(T).*;
            const comp_id = ecs.id(T);
            var i: usize = 0;
            while (i < self.iter.term_count) : (i += 1) {
                if (self.iter.terms[i].id == comp_id) return i;
            }
            unreachable;
        }

        /// gets a term that is not optional
        pub fn get(self: @This(), comptime T: type) *T {
            const index = self.getTermIndex(T);
            const column_index = self.iter.terms[index].index;
            return &ecsu.column(&self.iter, T, column_index + 1)[self.index - 1];
        }

        /// gets a term that is not optional but is readonly
        pub fn getConst(self: @This(), comptime T: type) *const T {
            const index = self.getTermIndex(T);
            const column_index = self.iter.terms[index].index;
            std.debug.assert(ecs.ecs_field_is_readonly(&self.iter, @intCast(index + 1)));

            // const column_index = ecs.ecs_iter_find_column(&self.iter, ecsu.meta.componentHandle(T).*);
            return &ecsu.column(&self.iter, T, column_index + 1)[self.index - 1];
        }

        /// gets a term that is optional. Returns null if it isnt found.
        pub fn getOpt(self: @This(), comptime T: type) ?*T {
            const index = self.getTermIndex(T);
            const column_index = self.iter.terms[index].index;
            var skip_term = ecs.id(T) != ecs.ecs_term_id(&self.iter, @intCast(column_index + 1));
            if (skip_term) return null;

            if (ecsu.columnOpt(&self.iter, T, column_index + 1)) |col| {
                return &col[self.index - 1];
            }
            return null;
        }

        /// gets a term that is optional and readonly. Returns null if it isnt found.
        pub fn getConstOpt(self: @This(), comptime T: type) ?*const T {
            const index = self.getTermIndex(T);
            std.debug.assert(ecs.ecs_field_is_readonly(&self.iter, @as(i32, @intCast(index + 1))));

            const column_index = self.iter.terms[index].index;
            var skip_term = ecs.id(T) != ecs.ecs_term_id(&self.iter, @as(usize, @intCast(column_index + 1)));
            if (skip_term) return null;

            if (ecsu.columnOpt(&self.iter, T, column_index + 1)) |col| {
                return &col[self.index - 1];
            }
            return null;
        }
    };

    pub fn init(world: *ecs.world_t, desc: *ecs.filter_desc_t) @This() {
        std.debug.assert(desc.storage == null);
        var filter_storage = std.heap.c_allocator.create(ecs.filter_t) catch unreachable;
        @memset(@as([*]u8, @ptrCast(filter_storage))[0..@sizeOf(ecs.filter_t)], 0);

        filter_storage.hdr.magic = ecs.filter_t_magic;
        desc.storage = filter_storage;
        var out_filter = ecs.ecs_filter_init(world, desc);
        std.debug.assert(out_filter != null);
        var filter = @This(){
            .world = world,
            .filter = out_filter,
        };
        return filter;
    }

    pub fn deinit(self: *@This()) void {
        ecs.ecs_filter_fini(self.filter);
        std.heap.c_allocator.destroy(self.filter);
    }

    pub fn asString(self: *@This()) [*c]u8 {
        return ecs.ecs_filter_str(self.world, self.filter);
    }

    pub fn filterIterator(self: *@This()) FilterIterator {
        return FilterIterator.init(ecs.ecs_filter_iter(self.world, self.filter));
    }

    /// gets an iterator that let you iterate the tables and then it provides an inner iterator to interate entities
    pub fn tableIterator(self: *@This(), comptime Components: type) ecsu.TableIterator(Components) {
        temp_iter_storage = ecs.ecs_filter_iter(self.world, self.filter);
        return ecsu.TableIterator(Components).init(&temp_iter_storage, ecs.ecs_filter_next);
    }

    // storage for the iterator so it can be passed by reference. Do not in-flight two Filters at once!
    var temp_iter_storage: ecs.iter_t = undefined;

    /// gets an iterator that iterates all matched entities from all tables in one iteration. Do not create more than one at a time!
    pub fn iterator(self: *@This(), comptime Components: type) ecsu.Iterator(Components) {
        temp_iter_storage = ecs.ecs_filter_iter(self.world, self.filter);
        return ecsu.Iterator(Components).init(&temp_iter_storage, ecs.ecs_filter_next);
    }

    // /// allows either a function that takes 1 parameter (a struct with fields that match the components in the query) or multiple paramters
    // /// (each param should match the components in the query in order)
    // pub fn each(self: *@This(), comptime function: anytype) void {
    //     // dont allow BoundFn
    //     std.debug.assert(@typeInfo(@TypeOf(function)) == .Fn);
    //     comptime var arg_count = ecsu.meta.argCount(function);

    //     if (arg_count == 1) {
    //         const Components = @typeInfo(@TypeOf(function)).Fn.args[0].arg_type.?;

    //         var iter = self.iterator(Components);
    //         while (iter.next()) |comps| {
    //             @call(.{ .modifier = .always_inline }, function, .{comps});
    //         }
    //     } else {
    //         const Components = std.meta.ArgsTuple(@TypeOf(function));

    //         var iter = self.iterator(Components);
    //         while (iter.next()) |comps| {
    //             @call(.{ .modifier = .always_inline }, function, ecsu.meta.fieldsTuple(comps));
    //         }
    //     }
    // }
};
