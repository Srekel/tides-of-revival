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
    ptr_single_const: *const anyopaque,
    ptr_array: *anyopaque,
    ptr_array_const: *const anyopaque,
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

    pub fn clear(self: *Variant) *Variant {
        self.value = .unknown;
        self.tag = 0;
        self.array_count = 0;
        self.elem_size = 0;
        return self;
    }

    pub fn createPtr(ptr: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_single = ptr },
            .tag = tag,
            .array_count = 1,
            .elem_size = @as(u16, @intCast(@sizeOf(@TypeOf(ptr.*)))),
        };
    }

    pub fn createPtrOpaque(ptr: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_single = ptr },
            .tag = tag,
            .array_count = 1,
            .elem_size = 0,
        };
    }

    pub fn createPtrConst(ptr: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_single_const = ptr },
            .tag = tag,
            .array_count = 1,
            .elem_size = @as(u16, @intCast(@sizeOf(@TypeOf(ptr.*)))),
        };
    }

    pub fn createSlice(slice: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_array = slice.ptr },
            .tag = tag,
            .array_count = @as(u16, @intCast(slice.len)),
            .elem_size = @as(u16, @intCast(@sizeOf(@TypeOf(slice[0])))),
        };
    }

    pub fn createStringFixed(string: []const u8, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            // .value = .{ .ptr_array_const = string.ptr },
            .value = .{ .ptr_array_const = string.ptr },
            .tag = tag,
            .array_count = @as(u16, @intCast(string.len)),
            .elem_size = @as(u16, @intCast(@sizeOf(u8))),
        };
    }

    // pub fn createSliceConst(slice: anytype, tag: Tag) Variant {
    //     assert(tag != 0);
    //     return Variant{
    //         .value = .{ .ptr_array = @intFromPtr(slice.ptr) },
    //         .tag = tag,
    //         .count = slice.len,
    //         .elem_size = @intCast(u16, @sizeOf(slice.ptr.*)),
    //     };
    // }

    pub fn createInt64(int: anytype) Variant {
        return Variant{
            .value = .{ .int64 = @as(i64, @intCast(int)) },
            .tag = 0, // TODO
        };
    }

    pub fn createUInt64(int: anytype) Variant {
        return Variant{
            .value = .{ .uint64 = @as(u64, @intCast(int)) },
            .tag = 0, // TODO
        };
    }

    pub fn createBool(boolean: bool) Variant {
        return Variant{
            .value = .{ .boolean = boolean },
            .tag = 0, // TODO
        };
    }

    pub fn setPtr(self: *Variant, ptr: anytype, tag: Tag) void {
        assert(tag != 0);
        self.value = .{ .ptr_single = ptr };
        self.tag = tag;
        self.elem_size = @as(u16, @intCast(@sizeOf(ptr.*)));
    }

    pub fn setSlice(self: *Variant, slice: anytype, tag: Tag) void {
        assert(tag != 0);
        self.value = .{ .ptr = @intFromPtr(slice.ptr) };
        self.tag = tag;
        self.array_count = slice.len;
        self.elem_size = @as(u16, @intCast(@sizeOf(slice.ptr.*)));
    }

    pub fn setInt64(self: *Variant, int: anytype) void {
        self = .{ .value = .{ .int64 = @as(i64, @intCast(int)) } };
    }

    pub fn setUInt64(self: *Variant, int: anytype) void {
        self = .{ .value = .{ .uint64 = @as(u64, @intCast(int)) } };
    }

    pub fn setBool(self: *Variant, boolean: bool) void {
        self = .{ .value = .{ .boolean = boolean } };
    }

    pub fn getPtr(self: Variant, comptime T: type, tag: Tag) *T {
        assert(tag == self.tag);
        return @as(*T, @ptrCast(@alignCast(self.value.ptr_single)));
    }

    pub fn getPtrConst(self: Variant, comptime T: type, tag: Tag) *const T {
        assert(tag == self.tag);
        return @as(*const T, @ptrCast(@alignCast(self.value.ptr_single_const)));
    }

    pub fn getSlice(self: Variant, comptime T: type, tag: Tag) []T {
        assert(tag == self.tag);
        var ptr = @as([*]T, @ptrCast(@alignCast(self.value.ptr_array)));
        return ptr[0..self.array_count];
    }

    pub fn getSliceConst(self: Variant, comptime T: type, tag: Tag) []T {
        assert(tag == self.tag);
        var ptr = @as([*]T, @ptrCast(self.value.ptr_array_const));
        return ptr[0..self.array_count];
    }

    pub fn getStringConst(self: Variant, tag: Tag) []const u8 {
        assert(tag == self.tag);
        var ptr = @as([*]const u8, @ptrCast(self.value.ptr_array_const));
        return ptr[0..self.array_count];
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

    pub fn getBool(self: Variant) bool {
        const v = self.value;
        const u = v.boolean;
        return u;
        // return self.value.uint64;
    }
};
