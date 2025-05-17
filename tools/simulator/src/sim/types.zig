const std = @import("std");
const zm = @import("zmath");
const zigimg = @import("zigimg");

pub const Vec2 = struct {
    x: f32,
    y: f32,
    pub fn asSlice(self: *Vec2) []f32 {
        return (&self.x)[0..2];
    }
};

pub const Vec3 = [3]f32;
// pub const Vec3 = struct {
//     x: f32,
//     y: f32,
//     z: f32,
// };

pub const Size2D = struct {
    width: u64,
    height: u64,
    pub fn eql(self: Size2D, other: Size2D) bool {
        return std.meta.eql(self, other);
    }
    pub fn area(self: Size2D) u64 {
        return @as(u64, self.width) * self.height;
    }
};

pub const Rect = struct {
    bottom: u64 = 0,
    top: u64,
    left: u64 = 0,
    right: u64,
    pub fn createOriginSquare(width: u64) Rect {
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
        height_min: f32 = 0,
        height_max: f32 = 1,
        pixels: []ElemType = undefined,

        pub fn zeroClear(self: *Self) void {
            @memset(self.pixels, 0);
        }

        pub fn get(self: Self, x: anytype, y: anytype) ElemType {
            return self.pixels[x + y * self.size.width];
        }

        pub fn set(self: *Self, x: anytype, y: anytype, val: ElemType) void {
            self.pixels[x + y * self.size.width] = val;
        }

        pub fn byteCount(self: Self) usize {
            return @sizeOf(ElemType) * @as(usize, self.size.height) * self.size.width;
        }

        pub fn square(width: u64) Image(ElemType) {
            return .{ .size = .{
                .width = width,
                .height = width,
            } };
        }

        pub fn asBytes(self: Self) []u8 {
            return castSliceToSlice(u8, self.pixels);
            // return std.mem.asBytes(self.pixels);
        }

        pub fn copy(self: *Self, other: Self) void {
            std.debug.assert(self.size.eql(other.size));
            @memcpy(self.pixels, other.pixels);
            self.height_min = other.height_min;
            self.height_max = other.height_max;
        }

        pub fn copyPixels(self: *Self, pixels: [*]const ElemType) void {
            @memcpy(self.pixels, pixels);
        }

        pub fn swap(self: *Self, other: *Self) void {
            std.debug.assert(self.size.eql(other.size));
            const self_copy = self.*;
            self.* = other.*;
            other.* = self_copy;
        }

        pub fn remap(self: *Self, min: f32, max: f32) void {
            // TODO: Simdify/jobify

            for (0..self.size.area()) |i_pixel| {
                self.pixels[i_pixel] = zm.mapLinearV(self.pixels[i_pixel], self.height_min, self.height_max, min, max);
            }
            self.height_min = min;
            self.height_max = max;
        }
    };
}

pub const ImageF32 = Image(f32);
pub const ImageVec3 = Image([3]f32);
pub const ImageRGBA = Image(ColorRGBA);
pub const ImageGreyscale = Image(u8);

pub const Heightmap = struct {
    image: ImageF32,
    precision: f32 = 1,
};

pub fn image_preview_f32(image_in: ImageF32, preview_image: *ImageRGBA) void {
    const scale = [2]u64{
        image_in.size.width / preview_image.size.width,
        image_in.size.height / preview_image.size.height,
    };

    const scale_factor_u8 = 255 / image_in.height_max;
    for (0..preview_image.size.height) |y| {
        for (0..preview_image.size.width) |x| {
            const index_in_x = x * scale[0];
            const index_in_y = y * scale[1];
            const value_in = image_in.pixels[index_in_x + index_in_y * image_in.size.width];
            const value_out: u8 = @intFromFloat(@min(value_in * scale_factor_u8, 255));
            preview_image.pixels[x + y * preview_image.size.width][0] = value_out;
            preview_image.pixels[x + y * preview_image.size.width][1] = value_out;
            preview_image.pixels[x + y * preview_image.size.width][2] = value_out;
        }
    }
}

pub fn image_preview_f32_greyscale(image_in: ImageF32, preview_image: *ImageGreyscale) void {
    const scale = [2]u64{
        image_in.size.width / preview_image.size.width,
        image_in.size.height / preview_image.size.height,
    };

    std.debug.assert(image_in.height_min == 0);
    const scale_factor_u8 = 255 / image_in.height_max;

    for (0..preview_image.size.height) |y| {
        for (0..preview_image.size.width) |x| {
            const index_in_x = x * scale[0];
            const index_in_y = y * scale[1];
            const value_in = image_in.pixels[index_in_x + index_in_y * image_in.size.width];
            const value_out: u8 = @intFromFloat(value_in * scale_factor_u8);
            preview_image.pixels[x + y * preview_image.size.width] = value_out;
        }
    }
}

pub fn castSliceToSlice(comptime T: type, slice: anytype) []T {
    // Note; This is a workaround for @ptrCast not supporting this
    const bytes = std.mem.sliceAsBytes(slice);
    const new_slice = std.mem.bytesAsSlice(T, bytes);
    return @constCast(new_slice);
}

var image_index: i32 = 0;
pub fn saveImageF32(image_in: ImageF32, name: []const u8, heatmap: bool) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const pixel_format = if (heatmap) zigimg.PixelFormat.rgba32 else zigimg.PixelFormat.grayscale8;
    var image = zigimg.Image.create(
        allocator,
        image_in.size.width,
        image_in.size.height,
        pixel_format,
    ) catch unreachable;

    defer image.deinit();

    const scale_factor_u8 = 255 / image_in.height_max;

    for (0..image_in.size.height) |y| {
        for (0..image_in.size.width) |x| {
            const index = x + y * image_in.size.width;
            const value_in = image_in.pixels[index];
            const value_out: u8 = @intFromFloat(value_in * scale_factor_u8);
            image.pixels.grayscale8[index].value = value_out;
        }
    }

    image_index += 1;
    var buf: [100]u8 = undefined;
    const filename = std.fmt.bufPrint(&buf, "simulator_{}_{str}.png", .{
        image_index,
        name,
    }) catch unreachable;
    image.writeToFilePath(filename, .{ .png = .{} }) catch unreachable;
}

pub const WorldSettings = struct {
    size: Size2D,
    patch_resolution: u64 = 65,
    terrain_height_min: f32 = 0,
    terrain_height_max: f32 = 1000,
};

// pub fn PatchData(ElemType: type, patch_count_side: u32, patch_lod: u8) type {
pub fn PatchData(ElemType: type) type {
    return struct {
        const Self = @This();
        const Patch = std.ArrayList(ElemType);

        lod: u8,
        size: Size2D,
        patches: std.ArrayList(Patch),

        pub fn create(lod: u8, size: u64, initial_capacity_per_patch: u64, allocator: std.mem.Allocator) Self {
            var self = Self{
                .lod = lod,
                .size = .{ .width = size, .height = size },
                .patches = std.ArrayList(Patch).initCapacity(allocator, size * size) catch unreachable,
            };
            // self.patches.initCapacity(allocator, patch_count_side * patch_count_side) catch unreachable;
            self.patches.expandToCapacity();
            for (self.patches.items) |*patch| {
                patch.* = std.ArrayList(ElemType).initCapacity(allocator, initial_capacity_per_patch) catch unreachable;
            }
            return self;
        }

        pub fn destroy(self: *Self) void {
            _ = self; // autofix
            // TODO
        }

        pub fn getPatch(self: Self, x: anytype, y: anytype) []ElemType {
            return self.patches.items[x + y * self.size.width].items;
        }

        pub fn addToPatch(self: *Self, x: anytype, y: anytype, elem: ElemType) void {
            self.patches.items[x + y * self.size.width].append(elem) catch unreachable;
        }
    };
}

pub const PatchDataPts2d = PatchData([2]f32);
