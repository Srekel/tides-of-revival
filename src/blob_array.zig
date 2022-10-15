const std = @import("std");
const assert = std.debug.assert;
const Util = @import("util.zig");

/// An array of aligned byte blobs of a fixed (runtime determined size)
pub fn BlobArray(comptime alignment: u29) type {
    return struct {
        const Self = @This();

        list: std.ArrayList(u8) = undefined,
        blob_size: u64 = undefined,
        blob_start: u64 = undefined,
        blob_count: u64 = 0,

        pub fn create(allocator: std.mem.Allocator, blob_size: u64) Self {
            // HACK: Should handle resizing while maintaining alignment.

            var self: Self = .{};
            var blob_size_aligned = std.mem.alignForward(blob_size, alignment);
            self.list = std.ArrayList(u8).initCapacity(allocator, blob_size_aligned * 8) catch unreachable;
            self.blob_size = blob_size_aligned;
            self.list.resize(alignment) catch unreachable;
            var ptr_as_int = @ptrToInt(&self.list.items[0]);
            var ptr_alignment = ptr_as_int % alignment;
            self.blob_start = alignment - ptr_alignment;
            // std.debug.print("init {} {} {}\n", .{ ptr_as_int, ptr_alignment, blob_size_aligned });
            self.list.resize(self.blob_start) catch unreachable;
            // var ptr_as_int2 = @ptrToInt(&self.list.items[self.list.items.len - 1]);
            // var ptr_alignment2 = ptr_as_int2 % alignment;
            // std.debug.print("init {} {} {}\n", .{ ptr_as_int2, ptr_alignment2, self.list.items.len });
            return self;
        }

        pub fn addBlob(self: *Self) *align(alignment) anyopaque {
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr + self.blob_size;
            self.list.resize(size_new) catch unreachable;
            // std.debug.print("addBlob1 {} {} {}\n", .{ size_curr, size_new, self.blob_start });
            // var ptr_as_int = @ptrToInt(&self.list.items[size_curr]);
            // var ptr_alignment = ptr_as_int % alignment;
            // std.debug.print("addBlob2 {} {} {}\n", .{ ptr_as_int, ptr_alignment, self.list.items.len });
            var aligned_ptr = @alignCast(alignment, &self.list.items[size_curr]);
            return aligned_ptr;
        }

        pub fn popBlob(self: *Self) *align(alignment) anyopaque {
            self.blob_count -= 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr - self.blob_size;
            self.list.resize(size_new) catch unreachable;
            var aligned_ptr = @alignCast(alignment, &self.list.items[size_new]);
            return aligned_ptr;
        }

        pub fn pushBlob(self: *Self, blob: *anyopaque) void {
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr - self.blob_size;
            self.list.resize(size_new) catch unreachable;
            var aligned_ptr_dst = @alignCast(alignment, &self.list.items[size_curr]);
            Util.memcpy(aligned_ptr_dst, blob, self.blob_size);
        }

        pub fn pushInstanceAsBlob(self: *Self, instance: anytype) void {
            const instance_size = @sizeOf(@TypeOf(instance));
            std.debug.assert(instance_size <= self.blob_size);
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr - self.blob_size;
            self.list.resize(size_new) catch unreachable;
            var aligned_ptr_dst = @alignCast(alignment, &self.list.items[size_curr]);
            Util.memcpy(aligned_ptr_dst, &instance, instance_size);
        }

        pub fn getBlob(self: *Self, index: u64) *align(alignment) anyopaque {
            const blob_byte_index = self.blob_start + index * self.blob_size;
            var aligned_ptr = @alignCast(alignment, &self.list.items[blob_byte_index]);
            return aligned_ptr;
        }

        pub fn getBlobAsInstance(self: *Self, index: u64, comptime T: type) *align(@alignOf(T)) T {
            const instance_size = @sizeOf(T);
            std.debug.assert(instance_size <= self.blob_size);
            const blob_byte_index = self.blob_start + index * self.blob_size;
            var aligned_ptr = @alignCast(@alignOf(T), &self.list.items[blob_byte_index]);
            const instance_ptr = @ptrCast(*T, aligned_ptr);
            return instance_ptr;
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
    var vec3 = ba.getBlobAsInstance(3, Vec3);
    // std.testing.expect(blob2b == blob2);
    // std.testing.expect(blob2b == blob2);
    // std.testing.expect(&blob2b == &vec2b);
    try std.testing.expect(vec2b.x == 2);
    try std.testing.expect(vec2b.x == vec3.x);
    try std.testing.expect(vec2b != vec3);
}
