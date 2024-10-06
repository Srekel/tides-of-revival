const std = @import("std");

pub const fn_node = *const fn (context: *Context) void;
pub const fn_node2 = *const fn (context: *Context) void;

pub const Resource = opaque {};
pub const Preview = struct {
    data: []u8,
};

pub const Context = struct {
    next_nodes: std.BoundedArray(fn_node2, 16) = .{},
    resources: std.StringHashMap(*anyopaque) = undefined,
    previews: std.StringHashMap(Preview) = undefined,
};
