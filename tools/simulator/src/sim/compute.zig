const std = @import("std");
const types = @import("types.zig");
const graph = @import("graph.zig");
const nodes = @import("nodes/nodes.zig");

pub var compute_fn: graph.fn_compute = undefined;
var id: i32 = 0;
var textbuf: [1024]u8 = .{};

pub fn compute_f32_1(compute_id: graph.ComputeId, image_in_1: ?*types.ImageF32, image_out_1: *types.ImageF32, data: anytype) void {
    const dispatch_image = switch (compute_id) {
        .downsample => image_out_1,
        .fbm => image_out_1,
        else => image_in_1.?,
    };
    var compute_info = graph.ComputeInfo{
        .compute_id = compute_id,
        .in_buffers = .{graph.ComputeBuffer{
            .data = if (image_in_1 != null) image_in_1.?.pixels.ptr else undefined,
            .width = @as(u32, @intCast(if (image_in_1 != null) image_in_1.?.size.width else 0)),
            .height = @as(u32, @intCast(if (image_in_1 != null) image_in_1.?.size.height else 0)),
        }} ++ ([_]graph.ComputeBuffer{.{}} ** 7),
        .out_buffers = .{graph.ComputeBuffer{
            .data = image_out_1.pixels.ptr,
            .width = @as(u32, @intCast(image_out_1.size.width)),
            .height = @as(u32, @intCast(image_out_1.size.height)),
        }} ++ ([_]graph.ComputeBuffer{.{}} ** 7),
        .in_count = if (image_in_1 != null) 1 else 0,
        .out_count = 1,
        .data_size = @sizeOf(@TypeOf(data)),
        .data = std.mem.asBytes(&data),
        .dispatch_size = .{ @intCast(dispatch_image.size.width), @intCast(dispatch_image.size.height) },
    };

    compute_fn(&compute_info);
}

pub fn compute_f32_n(compute_id: graph.ComputeId, images_in: []*types.ImageF32, images_out: []*types.ImageF32, data: anytype) void {
    var compute_info = graph.ComputeInfo{
        .compute_id = compute_id,
        .in_buffers = ([_]graph.ComputeBuffer{.{}} ** 8),
        .out_buffers = ([_]graph.ComputeBuffer{.{}} ** 8),
        .in_count = @intCast(images_in.len),
        .out_count = @intCast(images_out.len),
        .data_size = @sizeOf(@TypeOf(data)),
        .data = std.mem.asBytes(&data),
        .dispatch_size = .{
            @intCast(images_in[0].size.width),
            @intCast(images_in[0].size.height),
        },
    };

    for (images_in, compute_info.in_buffers[0..images_in.len]) |image_in, *in_buffer| {
        in_buffer.data = image_in.pixels.ptr;
        in_buffer.width = @intCast(image_in.size.width);
        in_buffer.height = @intCast(image_in.size.height);
    }

    for (images_out, compute_info.out_buffers[0..images_out.len]) |image_out, *out_buffer| {
        out_buffer.data = image_out.pixels.ptr;
        out_buffer.width = @intCast(image_out.size.width);
        out_buffer.height = @intCast(image_out.size.height);
    }

    compute_fn(&compute_info);
}

pub fn compute_reduce_f32_1(compute_id: graph.ComputeId, operator_id: graph.ComputeOperatorId, image_in_1: *types.ImageF32, image_out_1: *types.ImageF32) void {
    var compute_info = graph.ComputeInfo{
        .compute_id = compute_id,
        .compute_operator_id = operator_id,
        .in_buffers = .{graph.ComputeBuffer{
            .data = image_in_1.pixels.ptr,
            .width = @as(u32, @intCast(image_in_1.size.width)),
            .height = @as(u32, @intCast(image_in_1.size.height)),
        }} ++ ([_]graph.ComputeBuffer{.{}} ** 7),
        .out_buffers = .{graph.ComputeBuffer{
            .data = image_out_1.pixels.ptr,
            .width = @as(u32, @intCast(image_out_1.size.width)),
            .height = @as(u32, @intCast(image_out_1.size.height)),
        }} ++ ([_]graph.ComputeBuffer{.{}} ** 7),
        .in_count = 1,
        .out_count = 1,
        .data_size = 0,
        .data = null,
        .dispatch_size = .{
            @intCast(image_in_1.size.width),
            @intCast(image_in_1.size.height),
        },
    };

    compute_fn(&compute_info);
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

pub fn min(image_in: *types.ImageF32, scratch: *types.ImageF32) void {
    compute_reduce_f32_1(.reduce, .min, image_in, scratch);
    image_in.height_min = scratch.pixels[0];
}

pub fn max(image_in: *types.ImageF32, scratch: *types.ImageF32) void {
    compute_reduce_f32_1(.reduce, .max, image_in, scratch);
    image_in.height_max = scratch.pixels[0];
}

pub const GenerateFBMSettings = extern struct {
    width: u32,
    height: u32,
    seed: i32,
    frequency: f32,
    octaves: u32,
    scale: f32,
    _padding: [2]f32,
};

pub fn fbm(image_out: *types.ImageF32, settings: GenerateFBMSettings) void {
    compute_f32_1(.fbm, null, image_out, settings);
}

pub fn upsample_blur(image_in: *types.ImageF32, image_out: *types.ImageF32) void {
    const settings: extern struct {
        buffer_width: u32,
        buffer_height: u32,
        padding: [2]f32 = undefined,
    } = .{
        .buffer_width = @intCast(image_in.size.width),
        .buffer_height = @intCast(image_in.size.height),
    };
    compute_f32_1(.upsample_bilinear, image_in, image_out, settings);
}

pub fn downsample(image_in: *types.ImageF32, scratch_image: *types.ImageF32, image_out: *types.ImageF32, op: graph.ComputeOperatorId) void {
    const settings: extern struct {
        buffer_width: u32,
        buffer_height: u32,
        op: graph.ComputeOperatorId,
        padding: f32 = undefined,
    } = .{
        .buffer_width = @intCast(image_in.size.width / 2),
        .buffer_height = @intCast(image_in.size.height / 2),
        .op = op,
    };

    // TODO: Clear image_out depending on op?
    scratch_image.size.width = image_in.size.width / 2;
    scratch_image.size.height = image_in.size.height / 2;
    compute_f32_1(.downsample, image_in, scratch_image, settings);
    image_out.size.width = image_in.size.width / 2;
    image_out.size.height = image_in.size.height / 2;
    image_out.swap(scratch_image);

    min(image_out, scratch_image);
    max(image_out, scratch_image);
    nodes.math.rerangify(image_out);
}

pub fn upsample(image_in: *types.ImageF32, scratch_image: *types.ImageF32, image_out: *types.ImageF32, op: graph.ComputeOperatorId) void {
    const settings: extern struct {
        buffer_width: u32,
        buffer_height: u32,
        op: graph.ComputeOperatorId,
        padding: f32 = undefined,
    } = .{
        .buffer_width = @intCast(image_in.size.width),
        .buffer_height = @intCast(image_in.size.height),
        .op = op,
    };

    // TODO: Clear image_out depending on op?
    scratch_image.size.width = image_in.size.width * 2;
    scratch_image.size.height = image_in.size.height * 2;
    compute_f32_1(.upsample, image_in, scratch_image, settings);
    image_out.size = scratch_image.size;
    image_out.swap(scratch_image);
}

const BlurSettings = struct {
    buffer_width: u32,
    buffer_height: u32,
    sigma: f32 = 256.0,
    support: f32 = 0.995,
};
pub fn blur(image_in: *types.ImageF32, scratch: *types.ImageF32, image_out: *types.ImageF32) void {
    const settings: BlurSettings = .{
        .buffer_width = @intCast(image_in.size.width),
        .buffer_height = @intCast(image_in.size.height),
    };
    compute_f32_1(.gaussian_blur_horizontal, image_in, scratch, settings);
    compute_f32_1(.gaussian_blur_vertical, scratch, image_out, settings);
}

const RemapSettings = extern struct {
    from_min: f32,
    from_max: f32,
    to_min: f32,
    to_max: f32,
    width: u32,
    height: u32,
    _padding: [2]f32 = undefined,
};

pub fn remap(image_in: *types.ImageF32, image_out: *types.ImageF32, to_min: f32, to_max: f32) void {
    compute_f32_1(.remap, image_in, image_out, RemapSettings{
        .from_min = image_in.height_min,
        .from_max = image_in.height_max,
        .to_min = to_min,
        .to_max = to_max,
        .width = @intCast(image_in.size.width),
        .height = @intCast(image_in.size.height),
    });
    image_out.height_min = to_min;
    image_out.height_max = to_max;
    image_in.swap(image_out);
}

const SquareSettings = extern struct {
    width: u32,
    height: u32,
    _padding: [2]f32 = undefined,
};

pub fn square(image_in: *types.ImageF32, image_out: *types.ImageF32) void {
    compute_f32_1(.square, image_in, image_out, SquareSettings{
        .width = @intCast(image_in.size.width),
        .height = @intCast(image_in.size.height),
    });
    image_out.height_min = image_in.height_min * image_in.height_min;
    image_out.height_max = image_in.height_max * image_in.height_max;
    image_in.swap(image_out);
}

const MathSettings = extern struct {
    width: u32,
    height: u32,
    _padding: [2]f32 = undefined,
};

pub fn math_add(image_in0: *types.ImageF32, image_in1: *types.ImageF32, image_out: *types.ImageF32) void {
    std.debug.assert(image_in0.byteCount() == image_in1.byteCount() and image_in0.byteCount() == image_out.byteCount());
    std.debug.assert(image_in0 != image_out and image_in1 != image_out);
    var in_buffers = [_]*types.ImageF32{ image_in0, image_in1 };
    var out_buffers = [_]*types.ImageF32{image_out};

    compute_f32_n(
        .add,
        in_buffers[0..],
        out_buffers[0..],
        MathSettings{
            .width = @intCast(image_in0.size.width),
            .height = @intCast(image_in0.size.height),
        },
    );

    nodes.math.rerangify(image_out);
}

pub fn math_multiply(image_in0: *types.ImageF32, image_in1: *types.ImageF32, image_out: *types.ImageF32) void {
    std.debug.assert(image_in0.byteCount() == image_in0.byteCount() and image_in0.byteCount() == image_out.byteCount());
    var in_buffers = [_]*types.ImageF32{ image_in0, image_in1 };
    var out_buffers = [_]*types.ImageF32{image_out};

    compute_f32_n(
        .multiply,
        in_buffers[0..],
        out_buffers[0..],
        MathSettings{
            .width = @intCast(image_in0.size.width),
            .height = @intCast(image_in0.size.height),
        },
    );

    nodes.math.rerangify(image_out);
}

const TerraceSettings = extern struct {
    width: u32,
    height: u32,
    gradient_max: f32,
    _padding: [1]f32 = undefined,
};

pub fn terrace(gradient_in: *types.ImageF32, height_in: *types.ImageF32, height_out: *types.ImageF32) void {
    var gradient_out_img = types.ImageF32.square(gradient_in.size.width);
    gradient_out_img.pixels = std.heap.c_allocator.alloc(f32, height_in.pixels.len) catch unreachable;
    gradient_out_img.height_max = gradient_in.height_max;

    var in_buffers = [_]*types.ImageF32{ gradient_in, height_in };
    var out_buffers = [_]*types.ImageF32{
        height_out,
        &gradient_out_img,
    };
    compute_f32_n(
        .terrace,
        in_buffers[0..],
        out_buffers[0..],
        TerraceSettings{
            .width = @intCast(gradient_in.size.width),
            .height = @intCast(gradient_in.size.height),
            .gradient_max = gradient_in.height_max,
        },
    );
    height_out.height_min = height_in.height_min;
    height_out.height_max = height_in.height_max;
    height_in.swap(height_out);

    nodes.math.rerangify(&gradient_out_img);
    types.saveImageF32(gradient_out_img, "terrace_score", false);
}

const RemapData = struct {
    width: u32,
    height: u32,
    curve_keys_count: u32,
    _padding: u32 = undefined,
};

pub fn remapCurve(image_in: *types.ImageF32, curve: []const types.Vec2, image_out: *types.ImageF32) void {
    var curve_image: types.ImageF32 = .{ .size = .{
        .height = 1,
        .width = curve.len * 2,
    } };
    curve_image.pixels = std.heap.c_allocator.alloc(f32, curve_image.size.width * curve_image.size.height) catch unreachable;
    defer std.heap.c_allocator.free(curve_image.pixels);
    const floats = @as([*]const f32, @ptrCast(&curve[0].x));
    curve_image.copyPixels(floats);
    // nodes.math.rerangify(&curve_image);
    // types.saveImageF32(curve_image, "curve_image", false);

    var in_buffers = [_]*types.ImageF32{ image_in, &curve_image };
    var out_buffers = [_]*types.ImageF32{image_out};
    compute_f32_n(
        .remap_curve_linear,
        in_buffers[0..],
        out_buffers[0..],
        RemapData{
            .width = @intCast(image_in.size.width),
            .height = @intCast(image_in.size.height),
            .curve_keys_count = @intCast(curve.len),
        },
    );
}

const GatherPointsSettings = extern struct {
    width: u32,
    height: u32,
    world_width: f32,
    world_height: f32,
    threshold: f32,
    _padding: [3]f32 = undefined,
};

pub fn gatherPoints(image_in: *types.ImageF32, world_width: f32, world_height: f32, threshold: f32, points_out: *types.ImageVec2, counter_out: *types.ImageU32) void {
    const gather_points_data = GatherPointsSettings{
        .width = @as(u32, @intCast(image_in.size.width)),
        .height = @as(u32, @intCast(image_in.size.height)),
        .world_width = world_width,
        .world_height = world_height,
        .threshold = threshold,
    };

    counter_out.pixels[0] = 0;

    var compute_info = graph.ComputeInfo{
        .compute_id = .gather_points,
        .in_buffers = .{graph.ComputeBuffer{
            .buffer_type = .float,
            .data = image_in.pixels.ptr,
            .width = @as(u32, @intCast(image_in.size.width)),
            .height = @as(u32, @intCast(image_in.size.height)),
        }} ++ ([_]graph.ComputeBuffer{.{}} ** 7),
        .out_buffers = .{graph.ComputeBuffer{
            .buffer_type = .float2,
            .data = points_out.pixels.ptr,
            .width = @as(u32, @intCast(points_out.size.width)),
            .height = @as(u32, @intCast(points_out.size.height)),
        }} ++ .{graph.ComputeBuffer{
            .buffer_type = .uint,
            .data = counter_out.pixels.ptr,
            .width = @as(u32, @intCast(counter_out.size.width)),
            .height = @as(u32, @intCast(counter_out.size.height)),
        }} ++ ([_]graph.ComputeBuffer{.{}} ** 6),
        .in_count = 1,
        .out_count = 2,
        .data_size = @sizeOf(GatherPointsSettings),
        .data = std.mem.asBytes(&gather_points_data),
    };

    compute_fn(&compute_info);
}
