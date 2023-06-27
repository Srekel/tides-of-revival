const std = @import("std");
const assert = std.debug.assert;
const Util = @import("util.zig");

/// An array of aligned byte blobs of a fixed (runtime determined size)
pub fn BlobArray(comptime alignment: u29) type {
    return struct {
        const Self = @This();

        list: std.ArrayListAligned(u8, alignment),
        blob_size: u64,
        blob_count: u64 = 0,

        pub fn create(allocator: std.mem.Allocator, blob_size: u64) Self {
            const blob_size_aligned = std.mem.alignForward(usize, blob_size, alignment);

            // HACK: Should handle resizing while maintaining alignment.
            // TODO: Remove ...assumeCapacity
            const list = std.ArrayListAligned(u8, alignment).initCapacity(allocator, blob_size_aligned * 8) catch unreachable;

            return .{
                .list = list,
                .blob_size = blob_size_aligned,
            };
        }

        pub fn addBlob(self: *Self) u64 {
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr + self.blob_size;
            self.list.resize(size_new) catch unreachable;
            // std.debug.print("addBlob1 {} {} {}\n", .{ size_curr, size_new, self.blob_start });
            // var ptr_as_int = @intFromPtr(&self.list.items[size_curr]);
            // var ptr_alignment = ptr_as_int % alignment;
            // std.debug.print("addBlob2 {} {} {}\n", .{ ptr_as_int, ptr_alignment, self.list.items.len });
            // var aligned_ptr = @alignCast(alignment, &self.list.items[size_curr]);
            return self.blob_count - 1;
        }

        pub fn popBlob(self: *Self) []u8 {
            self.blob_count -= 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr - self.blob_size;
            self.list.resize(size_new) catch unreachable;
            return self.list[size_new..size_curr];
        }

        pub fn pushBlob(self: *Self, blob: []u8) u64 {
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            self.list.appendSliceAssumeCapacity(blob);
            const size_new = size_curr + self.blob_size;
            self.list.resize(size_new) catch unreachable;
            return self.blob_count - 1;
        }

        pub fn pushValueAsBlob(self: *Self, value: anytype) u64 {
            const value_size = @sizeOf(@TypeOf(value));
            std.debug.assert(value_size <= self.blob_size);
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr + self.blob_size;
            self.list.resize(size_new) catch unreachable;
            var aligned_ptr_dst = @alignCast(alignment, &self.list.items[size_curr]);
            Util.memcpy(aligned_ptr_dst, &value, value_size);
            return self.blob_count - 1;
        }

        pub fn getBlob(self: *Self, index: u64) []u8 {
            const blob_start = index * self.blob_size;
            const blob_end = (index + 1) * self.blob_size;
            return self.list.items[blob_start..blob_end];
        }

        pub fn getBlobAsValue(self: *Self, index: u64, comptime T: type) *T {
            const value_size = @sizeOf(T);
            std.debug.assert(value_size <= self.blob_size);
            const blob_byte_index = index * self.blob_size;
            var aligned_ptr = @alignCast(@alignOf(T), &self.list.items[blob_byte_index]);
            const value_ptr = @ptrCast(*T, aligned_ptr);
            return value_ptr;
        }
    };
}

test "blob_array" {
    const Vec3 = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
        // w: f32 = 0,
    };
    var ba = BlobArray(32).create(std.testing.allocator, 16);
    var blob0 = ba.addBlob();
    var blob1 = ba.addBlob();
    var blob2 = ba.addBlob();
    _ = blob0;
    var vec1: *Vec3 = @ptrCast(*Vec3, blob1);
    vec1.x = 1;
    var vec2: *Vec3 = @ptrCast(*Vec3, blob2);
    vec2.x = 2;
    // var blob2b = ba.getBlob(2);
    var vec2b = ba.getBlobAsInstance(2, Vec3);
    ba.pushInstanceAsBlob(vec2b.*);
    // var vec3 = ba.getBlobAsInstance(3, Vec3);
    // std.testing.expect(blob2b == blob2);
    // std.testing.expect(blob2b == blob2);
    // std.testing.expect(&blob2b == &vec2b);
    // try std.testing.expect(vec2b.x == 2);
    // try std.testing.expect(vec2b.x == vec3.x);
    // try std.testing.expect(vec2b != vec3);
}
