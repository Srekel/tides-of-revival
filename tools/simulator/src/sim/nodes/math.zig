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
