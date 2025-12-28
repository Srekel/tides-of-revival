const std = @import("std");

pub const ComputeId = enum(u32) {
    remap,
    square,
    gradient,
    fbm,
    upsample_blur,
    upsample_bilinear,
    upsample,
    downsample,
    terrace,
    multiply,
    add, // 10
    gaussian_blur_horizontal,
    gaussian_blur_vertical,
    remap_curve_linear,
    gather_points,
    erosion1, // 15
    erosion2,
    erosion3,
    erosion4,
    erosion5,
    reduce, // 20
};

pub const ComputeOperatorId = enum(u32) {
    none = 0,
    min = 1,
    max = 2,
    average = 3,
    nearest = 4,
    first = 5,
    sum = 6,
};

pub const ComputeBufferType = enum(u32) {
    float = 0,
    float2 = 1,
    float3 = 2,
    float4 = 3,
    uint = 4,
    erosion_struct = 5,
};

pub const ComputeBuffer = extern struct {
    buffer_type: ComputeBufferType = .float,
    data: *anyopaque = undefined,
    width: u32 = 0,
    height: u32 = 0,
};

pub const ComputeInfo = extern struct {
    compute_id: ComputeId,
    compute_sequence_length: u32 = 1,
    compute_iterations: u32 = 1,
    compute_operator_id: ComputeOperatorId = .none,
    in_buffers: [16]ComputeBuffer,
    out_buffers: [16]ComputeBuffer,
    in_count: u32,
    out_count: u32,
    data: [*c]const u8,
    data_size: u32,
    dispatch_size: [2]u32,
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
