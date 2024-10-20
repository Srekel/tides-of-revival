const std = @import("std");
const types = @import("../types.zig");
const znoise = @import("znoise");
const zm = @import("zmath");

pub fn gradient(image_in: types.ImageF32, height_ratio: f32, gradient_out: *types.ImageF32) void {
    const sobel_filter_x = [3][3]f32{ .{ -1, 0, 1 }, .{ -2, 0, 2 }, .{ -1, 0, 1 } };
    const sobel_filter_y = [3][3]f32{ .{ -1, -2, -1 }, .{ 0, 0, 0 }, .{ 1, 2, 1 } };

    var range_min: f32 = 10000;
    var range_max: f32 = 0;
    for (1..image_in.size.height - 1) |y1| {
        for (1..image_in.size.width - 1) |x1| {
            var sum_x: f32 = 0;
            var sum_y: f32 = 0;

            for (0..3) |y2| {
                for (0..3) |x2| {
                    sum_x += sobel_filter_x[x2][y2] * image_in.get(x1 + x2 - 1, y1 + y2 - 1) * height_ratio;
                    sum_y += sobel_filter_y[x2][y2] * image_in.get(x1 + x2 - 1, y1 + y2 - 1) * height_ratio;
                }
            }

            const gradient_value = std.math.sqrt(sum_x * sum_x + sum_y * sum_y);
            gradient_out.set(x1, y1, gradient_value);
            range_min = @min(range_min, gradient_value);
            range_max = @max(range_max, gradient_value);
        }
    }

    // gradient_out.height_min = range_min; // Not sure we want to do this?
    gradient_out.height_max = range_max;

    // Set corners/edges to be the same as their neighbors
    for (1..image_in.size.width - 1) |x1| {
        gradient_out.set(x1, 0, gradient_out.get(x1, 1));
        gradient_out.set(x1, image_in.size.height - 1, gradient_out.get(x1, image_in.size.height - 2));
    }
    for (0..image_in.size.height) |y1| {
        gradient_out.set(0, y1, gradient_out.get(1, y1));
        gradient_out.set(image_in.size.width - 1, y1, gradient_out.get(image_in.size.width - 2, y1));
    }
}
