const std = @import("std");
const types = @import("../types.zig");
const znoise = @import("znoise");

pub const FbmSettings = struct {
    octaves: u8,
    frequency: f32,
    rect: types.Rect,
    // resolution_inv: u32,
};

pub fn fbm(settings: *const FbmSettings, image: *types.ImageF32) void {
    const noise: znoise.FnlGenerator = .{
        .seed = @as(i32, 12345),
        .fractal_type = .fbm,
        .frequency = settings.frequency,
        .octaves = settings.octaves,
    };

    const res_inv = settings.rect.size().width / image.size.width;

    for (settings.rect.bottom..settings.rect.top) |z| {
        const z_sample = z * res_inv;
        for (settings.rect.left..settings.rect.right) |x| {
            const x_sample = x * res_inv;

            var value: f32 = noise.noise2(
                @as(f32, @floatFromInt(x_sample)) * 0.001,
                @as(f32, @floatFromInt(z_sample)) * 0.001,
            ) * 0.5 + 0.5;

            value = std.math.clamp(value, 0, 1);

            const x_image = (x - settings.rect.left) / res_inv;
            const z_image = (z - settings.rect.bottom) / res_inv;
            image.pixels[x_image + z_image * settings.rect.size().width] = value;
        }
    }
}