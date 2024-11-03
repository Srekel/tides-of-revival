const std = @import("std");
const types = @import("types.zig");
const graph = @import("graph.zig");

pub var compute_fn: graph.fn_compute = undefined;

pub fn compute_f32_1(compute_id: graph.ComputeId, image_in_1: *types.ImageF32, image_out_1: *types.ImageF32, data: anytype) void {
    var compute_info_gradient = graph.ComputeInfo{
        .compute_id = compute_id,
        .buffer_width = @intCast(image_in_1.size.width),
        .buffer_height = @intCast(image_in_1.size.height),
        .in = image_in_1.pixels.ptr,
        .out = image_out_1.pixels.ptr,
        .data_size = @sizeOf(@TypeOf(data)),
        .data = std.mem.asBytes(&data),
    };
    compute_fn(&compute_info_gradient);
}

pub const GradientData = extern struct {
    g_buffer_width: u32,
    g_buffer_height: u32,
    g_height_ratio: f32,
    _padding: f32 = 0,
};

pub fn gradient(heightmap_in: *types.ImageF32, gradient_out: *types.ImageF32, height_ratio: f32) void {
    const gradient_data = GradientData{
        .g_buffer_width = @intCast(heightmap_in.size.width),
        .g_buffer_height = @intCast(heightmap_in.size.height),
        .g_height_ratio = height_ratio,
    };

    compute_f32_1(.gradient, heightmap_in, gradient_out, gradient_data);
}
