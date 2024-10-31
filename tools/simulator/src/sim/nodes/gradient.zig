const std = @import("std");
const types = @import("../types.zig");
const znoise = @import("znoise");
const zm = @import("zmath");

pub fn gradient(image_in: types.ImageF32, height_ratio: f32, gradient_out: *types.ImageF32) void {
    const sobel_filter_x = [3][3]f32{
        .{ -1, 0, 1 },
        .{ -2, 0, 2 },
        .{ -1, 0, 1 },
    };
    const sobel_filter_y = [3][3]f32{
        .{ -1, -2, -1 },
        .{ 0, 0, 0 },
        .{ 1, 2, 1 },
    };

    var range_min: f32 = 10000;
    var range_max: f32 = 0;
    for (1..image_in.size.height - 1) |y1| {
        for (1..image_in.size.width - 1) |x1| {
            var sum_x: f32 = 0;
            var sum_y: f32 = 0;

            for (0..3) |y2| {
                for (0..3) |x2| {
                    sum_x += sobel_filter_x[y2][x2] * image_in.get(x1 + x2 - 1, y1 + y2 - 1) * height_ratio;
                    sum_y += sobel_filter_y[y2][x2] * image_in.get(x1 + x2 - 1, y1 + y2 - 1) * height_ratio;
                }
            }

            const gradient_value = std.math.sqrt(sum_x * sum_x + sum_y * sum_y);
            gradient_out.set(x1, y1, gradient_value);
            range_min = @min(range_min, gradient_value);
            range_max = @max(range_max, gradient_value);
        }
    }

    gradient_out.height_min = range_min;
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

pub fn laplace(image_in: types.ImageF32, height_ratio: f32, image_out: *types.ImageF32) void {
    _ = height_ratio; // autofix
    const kernel = [3][3]f32{
        .{ -1, -1, -1 },
        .{ -1, 8, -1 },
        .{ -1, -1, -1 },
    };

    // var range_min: f32 = 10000;
    var range_max: f32 = 0;
    for (1..image_in.size.height - 1) |y1| {
        for (1..image_in.size.width - 1) |x1| {
            var sum: f32 = 0;

            for (0..3) |y2| {
                for (0..3) |x2| {
                    sum += kernel[x2][y2] * image_in.get(x1 + x2 - 1, y1 + y2 - 1);
                }
            }

            image_out.set(x1, y1, @max(0, sum));
            // range_min = @min(range_min, gradient_value);
            range_max = @max(range_max, sum);
        }
    }

    // image_out.height_min = range_min; // Not sure we want to do this?
    image_out.height_max = range_max;

    // Set corners/edges to be the same as their neighbors
    for (1..image_in.size.width - 1) |x1| {
        image_out.set(x1, 0, image_out.get(x1, 1));
        image_out.set(x1, image_in.size.height - 1, image_out.get(x1, image_in.size.height - 2));
    }
    for (0..image_in.size.height) |y1| {
        image_out.set(0, y1, image_out.get(1, y1));
        image_out.set(image_in.size.width - 1, y1, image_out.get(image_in.size.width - 2, y1));
    }
}

pub fn terrace(image_in: types.ImageF32, gradient_in: types.ImageF32, image_out: *types.ImageF32, scratch_image: *types.ImageF32) void {
    scratch_image.zeroClear();

    var range_min: f32 = 1000000;
    var range_max: f32 = 0;
    const SCALE = 5;
    for (SCALE * 2..image_in.size.height - SCALE * 2) |y1| {
        for (SCALE * 2..image_in.size.width - SCALE * 2) |x1| {
            const gradient_value = gradient_in.get(x1, y1) / gradient_in.height_max;
            const gradient_effect = std.math.clamp(1 - gradient_value, 0, 1);
            const height_value1 = image_in.get(x1, y1);

            for (0..5) |y2| {
                for (0..5) |x2| {
                    const x2f: f32 = @floatFromInt(x2);
                    const y2f: f32 = @floatFromInt(y2);
                    const distance_effect = 1 - ((x2f - 2) * (x2f - 2) + (y2f - 2) * (y2f - 2)) / 10;
                    const effect_clamped = std.math.clamp(distance_effect * gradient_effect, 0, 1);
                    const height_value2 = image_in.get(x1 + x2 * SCALE - 2 * SCALE, y1 + y2 * SCALE - 2 * SCALE);
                    // image_out.set(x1 + x2 - 1, y1 + y2 - 1, std.math.lerp(height_value2, height_value1, effect_clamped));

                    if (effect_clamped < scratch_image.get(x1 + x2 * SCALE - 2 * SCALE, y1 + y2 * SCALE - 2 * SCALE)) {
                        continue;
                    }
                    scratch_image.set(x1 + x2 * SCALE - 2 * SCALE, y1 + y2 * SCALE - 2 * SCALE, effect_clamped);

                    const value = std.math.lerp(height_value2, height_value1, effect_clamped);
                    image_out.set(
                        x1 + x2 * SCALE - 2 * SCALE,
                        y1 + y2 * SCALE - 2 * SCALE,
                        value,
                    );
                    range_min = @min(range_min, value);
                    range_max = @max(range_max, value);
                }
            }
        }
    }

    image_out.height_min = range_min;
    image_out.height_max = range_max;
}
