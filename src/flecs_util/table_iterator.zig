const std = @import("std");
const ecs = @import("zflecs");
const ecsu = @import("flecs_util.zig");

pub fn TableIterator(comptime Components: type) type {
    std.debug.assert(@typeInfo(Components) == .Struct);

    const Columns = ecsu.meta.TableIteratorData(Components);

    return struct {
        pub const InnerIterator = struct {
            data: Columns = undefined,
            count: i32,
        };

        iter: *ecs.iter_t,
        nextFn: fn ([*c]ecs.iter_t) callconv(.C) bool,

        pub fn init(iter: *ecs.iter_t, nextFn: fn ([*c]ecs.iter_t) callconv(.C) bool) @This() {
            ecsu.meta.validateIterator(Components, iter);
            return .{
                .iter = iter,
                .nextFn = nextFn,
            };
        }

        pub fn tableType(self: *@This()) ecsu.Type {
            return ecsu.Type.init(self.iter.world.?, self.iter.type);
        }

        pub fn skip(self: *@This()) void {
            ecsu.meta.assertMsg(self.nextFn == ecs.query_next, "skip only valid on Queries!", .{});
            ecs.query_skip(self.iter);
        }

        pub fn next(self: *@This()) ?InnerIterator {
            if (!self.nextFn(self.iter)) return null;

            var iter: InnerIterator = .{ .count = self.iter.count };
            var index: usize = 0;
            inline for (@typeInfo(Components).Struct.fields, 0..) |field, i| {
                // skip filters since they arent returned when we iterate
                while (self.iter.terms[index].inout == .InOutNone) : (index += 1) {}

                const is_optional = @typeInfo(field.type) == .Optional;
                const col_type = ecsu.meta.FinalChild(field.type);
                if (ecsu.meta.isConst(field.type)) std.debug.assert(ecs.field_is_readonly(self.iter, i + 1));

                if (is_optional) @field(iter.data, field.name) = null;
                const column_index = self.iter.terms[index].index;
                const skip_term = if (is_optional) ecsu.meta.componentId(self.iter.world.?, col_type).* != ecs.term_id(&self.iter, @intCast(column_index + 1)) else false;

                // note that an OR is actually a single term!
                // std.debug.print("---- col_type: {any}, optional: {any}, i: {d}, col_index: {d}\n", .{ col_type, is_optional, i, column_index });
                if (!skip_term) {
                    if (ecsu.columnOpt(self.iter, col_type, column_index + 1)) |col| {
                        @field(iter.data, field.name) = col;
                    }
                }
                index += 1;
            }

            return iter;
        }
    };
}
