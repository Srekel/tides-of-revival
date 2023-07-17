const std = @import("std");
const ecs = @import("zflecs");

/// returns the column at index
pub fn column(iter: [*c]const ecs.iter_t, comptime T: type, index: i32) [*]T {
    var col = ecs.field_w_size(iter, @sizeOf(T), index);
    return @ptrCast(@alignCast(col));
}

/// returns null in the case of column not being present or an invalid index
pub fn columnOpt(iter: [*c]const ecs.iter_t, comptime T: type, index: i32) ?[*]T {
    if (index <= 0) return null;
    var col = ecs.field_w_size(iter, @sizeOf(T), index);
    if (col == null) return null;
    return @ptrCast(@alignCast(col));
}

/// used with ecs_iter_find_column to fetch data from terms not in the query
pub fn columnNonQuery(iter: [*c]const ecs.iter_t, comptime T: type, index: i32) ?[*]T {
    if (index <= 0) return null;
    var col = ecs.iter_column_w_size(iter, @sizeOf(T), index - 1);
    if (col == null) return null;
    return @ptrCast(@alignCast(col));
}

/// used when the Flecs API provides untyped data to convert to type. Query/system order_by callbacks are one example.
pub fn componentCast(comptime T: type, val: ?*const anyopaque) *const T {
    return @ptrCast(@alignCast(val));
}
