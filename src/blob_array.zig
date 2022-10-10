const std = @import("std");
const assert = std.debug.assert;
const Util = @import("util.zig");

pub fn BlobArray(comptime alignment: u29) type {
    return struct {
        const Self = @This();
        const blob_alignment: u64 = alignment;

        list: std.ArrayList(u8) = undefined,
        blob_size: u64 = undefined,
        blob_count: u64 = 0,

        pub fn init(self: *Self, allocator: std.mem.Allocator, blob_size: u64) void {
            // HACK: Should handle resizing while maintaining alignment.
            self.list = std.ArrayList(u8).initCapacity(allocator, blob_size * 8) catch unreachable;
            self.blob_size = blob_size;
            while (true) {
                self.list.resize(self.list.items.len + 1) catch unreachable;
                const ptr_as_int = @ptrToInt(&self.list.items[self.list.items.len - 1]);
                if (ptr_as_int % blob_alignment == 0) {
                    break;
                }
            }
        }

        pub fn addBlob(self: *Self) *anyopaque {
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr + self.blob_size + blob_alignment;
            self.list.resize(size_new) catch unreachable;
            return &self.list.items[size_curr];
        }

        pub fn popBlob(self: *Self) *anyopaque {
            self.blob_count -= 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr - self.blob_size;
            self.list.resize(size_new) catch unreachable;
            return &self.list.items[size_new];
        }

        pub fn pushBlob(self: *Self, blob: *anyopaque) void {
            self.blob_count += 1;
            const size_curr = self.list.items.len;
            const size_new = size_curr - self.blob_size;
            self.list.resize(size_new) catch unreachable;
            Util.memcpy(&self.list.items[size_curr], blob, self.blob_size);
        }

        pub fn getBlob(self: *Self, index: u64) *anyopaque {
            return &self.list.items[index * self.blob_size];
        }
    };
}
