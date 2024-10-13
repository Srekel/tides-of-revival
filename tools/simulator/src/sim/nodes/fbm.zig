const std = @import("std");
const types = @import("../types.zig");
const znoise = @import("znoise");

pub const FbmSettings = struct {
    octaves: u8,
    frequency: f32,
};

pub fn fbm(settings: *const FbmSettings, image: *types.ImageF32) void {
    const noise: znoise.FnlGenerator = .{
        .seed = @as(i32, 12345),
        .fractal_type = .fbm,
        .frequency = settings.frequency,
        .octaves = settings.octaves,
    };

    for (0..settings.size[1]) |z| {
        for (0..settings.size[0]) |x| {
            var value: f32 = noise.noise2(
                @as(f32, @floatFromInt(x)),
                @as(f32, @floatFromInt(z)),
            ) * 0.5 + 0.5;
            value = std.math.clamp(value, 0, 1);
            image[x + z * settings.size[0]] = value;
        }
    }
}
