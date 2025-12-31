const std = @import("std");
const types = @import("../types.zig");
const zm = @import("zmath");

pub fn square(image: *types.ImageF32) void {
    for (image.pixels) |*pixel| {
        pixel.* = pixel.* * pixel.*;
    }
    image.height_min = image.height_min * image.height_min;
    image.height_max = image.height_max * image.height_max;
}

pub fn rerangify(image: *types.ImageF32) void {
    var range_min: f32 = 10000;
    var range_max: f32 = -10000;
    const pixel_count = image.size.area();
    for (image.pixels[0..pixel_count]) |pixel| {
        range_min = @min(range_min, pixel);
        range_max = @max(range_max, pixel);
    }
    image.height_min = range_min;
    image.height_max = range_max;
}

pub fn sub(image0: *types.ImageF32, image1: *types.ImageF32, image_out: *types.ImageF32) void {
    const pixel_count = image0.size.area();
    var range_min: f32 = 10000;
    var range_max: f32 = -10000;
    for (image0.pixels[0..pixel_count], image1.pixels[0..pixel_count], image_out.pixels[0..pixel_count], 0..) |pi0, pi1, *pixel, i| {
        _ = i; // autofix
        pixel.* = pi0 - pi1;
        range_min = @min(range_min, pixel.*);
        range_max = @max(range_max, pixel.*);
        // if (@abs(pi0 - pi1) > 10) {
        //     range_max = @max(range_max, pixel.*);
        //     std.log.info("lol {}, p0:{}, p1:{d}", .{ i, pi0, pi1 });
        // }
    }
    image_out.height_min = range_min;
    image_out.height_max = range_max;
}
