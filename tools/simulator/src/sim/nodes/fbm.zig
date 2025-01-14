const std = @import("std");
const types = @import("../types.zig");
const znoise = @import("znoise");
const zm = @import("zmath");

pub const FbmSettings = struct {
    seed: i32,
    octaves: u8,
    frequency: f32,
    rect: types.Rect,
    scale: f32,
};

pub fn fbm(settings: *const FbmSettings, image: *types.ImageF32) void {
    const noise: znoise.FnlGenerator = .{
        .seed = settings.seed,
        .fractal_type = .fbm,
        .frequency = settings.frequency,
        .octaves = settings.octaves,
    };

    const res_inv = settings.rect.size().width / image.size.width;
    var min: f32 = 10;
    var max: f32 = 0;

    for (settings.rect.bottom..settings.rect.top) |y| {
        const y_sample = y * res_inv;
        for (settings.rect.left..settings.rect.right) |x| {
            const x_sample = x * res_inv;

            var value: f32 = noise.noise2(
                @as(f32, @floatFromInt(x_sample)) * settings.scale,
                @as(f32, @floatFromInt(y_sample)) * settings.scale,
            ) * 0.5 + 0.5;

            value = std.math.clamp(value, 0, 1);

            const x_image = (x - settings.rect.left) / res_inv;
            const z_image = (y - settings.rect.bottom) / res_inv;
            image.pixels[x_image + z_image * settings.rect.size().width] = value;
            min = @min(min, value);
            max = @max(max, value);
        }
    }

    image.height_min = min;
    image.height_max = max;
}
