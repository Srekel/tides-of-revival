const std = @import("std");

pub const Size2D = struct {
    width: u16,
    height: u16,
    pub fn eql(self: Size2D, other: Size2D) bool {
        return std.meta.eql(self, other);
    }
    pub fn area(self: Size2D) u32 {
        return @as(u32, self.width) * self.height;
    }
};

pub const Rect = struct {
    bottom: u16 = 0,
    top: u16,
    left: u16 = 0,
    right: u16,
    pub fn createOriginSquare(width: u32) Rect {
        return .{
            .top = width,
            .right = width,
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
        const Self = @This();
        size: Size2D,
        pixels: []ElemType = undefined,

        pub fn byteCount(self: Self) usize {
            return @sizeOf(ElemType) * @as(usize, self.size.height) * self.size.width;
        }

        pub fn square(width: u16) Image(ElemType) {
            return .{ .size = .{
                .width = width,
                .height = width,
            } };
        }

        pub fn asBytes(self: Self) []u8 {
            return castSliceToSlice(u8, self.pixels);
            // return std.mem.asBytes(self.pixels);
        }

        pub fn copy(self: *Self, other: Self, allocator: std.mem.Allocator) void {
            std.debug.assert(self.size.eql(other.size));
            if (self.pixels.len == 0) {
                self.pixels = allocator.alignedAlloc(ElemType, 128, other.size.area()) catch unreachable;
            }
            @memcpy(self.pixels, other.pixels);
        }
    };
}

pub const ImageF32 = Image(f32);
pub const ImageRGBA = Image(ColorRGBA);

pub fn image_preview_f32(image_in: ImageF32, preview_image: *ImageRGBA) void {
    const scale = [2]u16{
        image_in.size.width / preview_image.size.width,
        image_in.size.height / preview_image.size.height,
    };

    for (0..preview_image.size.height) |y| {
        for (0..preview_image.size.width) |x| {
            const index_in_x = x * scale[0];
            const index_in_y = y * scale[1];
            const value_in = image_in.pixels[index_in_x + index_in_y * image_in.size.width];
            const value_out: u8 = @intFromFloat(value_in * 255);
            preview_image.pixels[x + y * preview_image.size.width][0] = value_out;
            preview_image.pixels[x + y * preview_image.size.width][1] = value_out;
            preview_image.pixels[x + y * preview_image.size.width][2] = value_out;
        }
    }
}

pub fn castSliceToSlice(comptime T: type, slice: anytype) []T {
    // Note; This is a workaround for @ptrCast not supporting this
    const bytes = std.mem.sliceAsBytes(slice);
    const new_slice = std.mem.bytesAsSlice(T, bytes);
    return new_slice;
}
