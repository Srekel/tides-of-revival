const std = @import("std");

pub const ComputeId = enum(u32) {
    remap,
    square,
    gradient,
    fbm,
    upsample_blur,
    reduce,
};

pub const ComputeOperatorId = enum(u32) {
    none = 0,
    min = 1,
    max = 2,
};

pub const ComputeInfo = extern struct {
    compute_id: ComputeId,
    compute_operator_id: ComputeOperatorId = .none,
    in: [*c]f32,
    out: [*c]f32,
    buffer_width_in: u32,
    buffer_height_in: u32,
    buffer_width_out: u32,
    buffer_height_out: u32,
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
