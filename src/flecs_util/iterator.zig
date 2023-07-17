const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util.zig");

pub fn Iterator(comptime Components: type) type {
    std.debug.assert(@typeInfo(Components) == .Struct);

    // converts the Components struct fields into pointer-to-many arrays
    const Columns = ecsu.meta.TableIteratorData(Components);

    // used internally to store the current tables columns and the array length
    const TableColumns = struct {
        columns: Columns = undefined,
        count: i32,
    };

    return struct {
        iter: *ecs.iter_t,
        inner_iter: ?TableColumns = null,
        index: usize = 0,
        nextFn: *const fn ([*c]ecs.iter_t) callconv(.C) bool,

        pub fn init(iter: *ecs.iter_t, comptime nextFn: fn ([*c]ecs.iter_t) callconv(.C) bool) @This() {
            ecsu.meta.validateIterator(Components, iter);
            return .{
                .iter = iter,
                .nextFn = nextFn,
            };
        }

        pub fn entity(self: *@This()) ecs.entity_t {
            return self.iter.entities[self.index - 1];
        }

        pub fn world(self: *@This()) ecsu.World {
            return .{ .world = self.iter.world.? };
        }

        pub fn tableType(self: *@This()) ecsu.Type {
            return ecsu.Type.init(self.iter.world.?, self.iter.type);
        }

        pub fn skip(self: *@This()) void {
            ecsu.meta.assertMsg(self.nextFn == ecs.ecs_query_next, "skip only valid on Queries!", .{});
            ecs.ecs_query_skip(&self.iter);
        }

        /// gets the next Entity from the query results if one is available
        pub inline fn next(self: *@This()) ?Components {
            // outer check for when we need to see if there is another table to iterate
            if (self.inner_iter == null) {
                self.inner_iter = self.nextTable();
                if (self.inner_iter == null) return null;
                self.index = 0;
            }

            var comps: Components = undefined;
            inline for (@typeInfo(Components).Struct.fields) |field| {
                var column = @field(self.inner_iter.?.columns, field.name);

                // for optionals, we have to unwrap the column since it is also optional
                if (@typeInfo(field.type) == .Optional) {
                    if (column) |col| {
                        @field(comps, field.name) = &col[self.index];
                    } else {
                        @field(comps, field.name) = null;
                    }
                } else {
                    @field(comps, field.name) = &column[self.index];
                }
            }

            self.index += 1;

            // check for iteration of the current tables completion. if its done null the inner_iter so we fetch the next one when called again
            if (self.index == self.inner_iter.?.count) self.inner_iter = null;

            return comps;
        }

        /// gets the next table from the query results if one is available. Fills the iterator with the columns from the table.
        inline fn nextTable(self: *@This()) ?TableColumns {
            if (!self.nextFn(self.iter)) return null;

            var iter: TableColumns = .{ .count = self.iter.count };
            var index: usize = 0;
            inline for (@typeInfo(Components).Struct.fields, 0..) |field, i| {
                // skip filters and EcsNothing masks since they arent returned when we iterate
                while (self.iter.terms[index].inout == .ecs_in_out_none or self.iter.terms[index].src.flags == ecs.IsEntity) : (index += 1) {}

                const is_optional = @typeInfo(field.type) == .Optional;
                const col_type = ecsu.meta.FinalChild(field.type);
                if (ecsu.meta.isConst(field.type)) std.debug.assert(ecs.ecs_field_is_readonly(self.iter, i + 1));

                if (is_optional) @field(iter.columns, field.name) = null;
                const column_index = self.iter.terms[index].field_index;
                const raw_term_id = ecs.ecs_field_id(self.iter, column_index + 1);
                const term_id = if (ecs.ecs_id_is_pair(raw_term_id)) ecs.pair_first(raw_term_id) else raw_term_id;
                var skip_term = if (is_optional) ecsu.meta.componentHandle(col_type).* != term_id else false;

                // note that an OR is actually a single term!
                // std.debug.print("---- col_type: {any}, optional: {any}, i: {d}, col_index: {d}, skip_term: {d}\n", .{ col_type, is_optional, i, column_index, skip_term });
                // std.debug.print("---- compId: {any}, term_id: {any}\n", .{ ecsu.meta.componentHandle(col_type).*, ecs.ecs_term_id(self.iter, @intCast(usize, column_index + 1)) });
                if (!skip_term) {
                    if (ecsu.columnOpt(self.iter, col_type, column_index + 1)) |col| {
                        @field(iter.columns, field.name) = col;
                    }
                }
                index += 1;
            }

            return iter;
        }
    };
}
