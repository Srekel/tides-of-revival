const std = @import("std");

pub const Size2D = struct {
    width: u16,
    height: u16,
};

pub const Rect = struct {
    bottom: u16 = 0,
    top: u16,
    left: u16 = 0,
    right: u16,
    pub fn createOriginSquare(width:u32) Rect {
        return .{
            .top = width,
            .right= width,
        };
    }
    pub fn size(self: Rect) Size2D {
        return .{
            .width = self.right - self.left,
            .height = self.top - self.bottom,
        };
    }
};

pub const ColorRGBA = [4]u8;

pub fn Image(ElemType: type) type {
    return struct {
        size: Size2D,
        pixels: []ElemType = undefined,

        pub fn square(width: u16) Image(ElemType) {
            return .{ .size = .{
                .width = width,
                .height = width,
            } };
        }
    };
}

pub const ImageF32 = Image(f32);
pub const ImageRGBA = Image(ColorRGBA);

pub fn image_preview(image_in: anytype, preview_image: *ImageRGBA) void {
    const scale = [2]u16{
        image_in.size.width / preview_image.size.width,
        image_in.size.height / preview_image.size.height,
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
