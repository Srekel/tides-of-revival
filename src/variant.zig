const std = @import("std");
const assert = std.debug.assert;
// const builtin = std.builtin;
// const TypeId = builtin.TypeId;

pub const Tag = u64;
pub const Hash = u64;

pub const VariantType = union(enum) {
    unknown: void,
    int64: i64,
    uint64: u64,
    boolean: bool,
    tag: Tag,
    hash: Hash,
    ptr_single: *anyopaque,
    ptr_array: *anyopaque,
};

comptime {
    // @compileLog("lol", @sizeOf(VariantType));
    assert(@sizeOf(VariantType) == 16);
}

pub const Variant = struct {
    value: VariantType = .unknown,
    tag: Tag = 0,
    array_count: u16 = 0,
    elem_size: u16 = 0,

    pub fn isUnset(self: Variant) bool {
        return self.value == .unknown;
    }

    pub fn createPtr(ptr: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_single = ptr },
            .tag = tag,
            .array_count = 1,
            .elem_size = @intCast(u16, @sizeOf(@TypeOf(ptr.*))),
        };
    }

    pub fn createSlice(slice: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_array = @ptrToInt(slice.ptr) },
            .tag = tag,
            .count = slice.len,
            .elem_size = @intCast(u16, @sizeOf(slice.ptr.*)),
        };
    }

    pub fn createInt64(int: anytype) Variant {
        return Variant{
            .value = .{ .int64 = @intCast(i64, int) },
            .tag = 0, // TODO
        };
    }
    pub fn createUInt64(int: anytype) Variant {
        return Variant{
            .value = .{ .uint64 = @intCast(u64, int) },
            .tag = 0, // TODO
        };
    }

    pub fn setPtr(self: *Variant, ptr: anytype, tag: Tag) void {
        assert(tag != 0);
        self.value = .{ .ptr_singler = @ptrToInt(ptr) };
        self.tag = tag;
        self.elem_size = @intCast(u16, @sizeOf(ptr.*));
    }

    pub fn setSlice(self: *Variant, slice: anytype, tag: Tag) void {
        assert(tag != 0);
        self.value = .{ .ptr = @ptrToInt(slice.ptr) };
        self.tag = tag;
        self.array_count = slice.len;
        self.elem_size = @intCast(u16, @sizeOf(slice.ptr.*));
    }

    pub fn setInt64(self: *Variant, int: anytype) void {
        self = .{ .value = .{ .int64 = @intCast(i64, int) } };
    }

    pub fn setUInt64(self: *Variant, int: anytype) void {
        self = .{ .value = .{ .uint64 = @intCast(u64, int) } };
    }

    pub fn getPtr(self: Variant, comptime T: type, tag: Tag) *T {
        assert(tag == self.tag);
        return @intToPtr(*T, self.value.ptr_single);
    }

    pub fn getSlice(self: Variant, comptime T: type, tag: Tag) []T {
        assert(tag == self.tag);
        var ptr = @intToPtr([*]T, self.value.ptr_array);
        return ptr[0..self.count];
    }

    pub fn getInt64(self: Variant) i64 {
        return self.value.int64;
    }

    pub fn getUInt64(self: Variant) u64 {
        const v = self.value;
        const u = v.uint64;
        return u;
        // return self.value.uint64;
    }
};
