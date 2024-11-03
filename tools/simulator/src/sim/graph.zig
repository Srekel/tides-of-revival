const std = @import("std");

pub const ComputeId = enum(u32) {
    remap = 0,
    square = 1,
    gradient = 2,
    fbm = 3,
    reduce = 4,
};

pub const ComputeInfo = extern struct {
    compute_id: ComputeId,
    compute_operator_id: enum(u32) {
        none = 0,
        min = 1,
        max = 2,
    } = .none,
    in: [*c]f32,
    out: [*c]f32,
    buffer_width: u32,
    buffer_height: u32,
    data: [*c]const u8,
    data_size: u32,
};

pub const fn_node = *const fn (context: *Context) void;
pub const fn_node2 = *const fn (context: *Context) void;
pub const fn_compute = *const fn (compute_info: ?*ComputeInfo) callconv(.C) void;

pub const Resource = opaque {};
pub const Preview = struct {
    data: []u8,
};

pub const Context = struct {
    next_nodes: std.BoundedArray(fn_node2, 16) = .{},
    resources: std.StringHashMap(*anyopaque) = undefined,
    previews: std.StringHashMap(Preview) = undefined,
    compute_fn: fn_compute = undefined,
};

pub const Graph = struct {
    pub const NodeLookup = u8;

    pub const Node = struct {
        name: []const u8,
        connections_out: []const NodeLookup = &.{},
    };

    nodes: []const Node,
};
