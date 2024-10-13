const std = @import("std");

pub const Size2D = union {
    data: [2]u32,
    wh: struct {
        width: u32,
        height: u32,
    },
};

pub const ColorRGBA = [4]u8;

pub fn Image(ElemType: type) type {
    return struct {
        size: Size2D,
        data: []ElemType,
    };
}

pub const ImageF32 = Image(f32);
pub const ImageRGBA = Image(ColorRGBA);

pub fn image_preview(image_in: anytype, in_range: []f32, preview_image: *ImageRGBA) void {
    _ = in_range; // autofix
    const scale: Size2D = .{
        image_in.size.data[0] / preview_image.size.data[0],
        image_in.size.data[1] / preview_image.size.data[1],
    };

    for (0..preview_image.size.wh.height) |z| {
        _ = z; // autofix
        for (0..preview_image.size.wh.width) |x| {
            _ = x; // autofix
            const index_in_x = image_in.size.wh.width / scale.wh.width;
            const index_in_y = image_in.size.wh.height / scale.wh.height;
            _ = index_in_y; // autofix
            _ = index_in_x; // autofix

        }
    }
}
