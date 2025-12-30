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
