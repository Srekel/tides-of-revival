const std = @import("std");
const assert = std.debug.assert;
// const builtin = std.builtin;
// const TypeId = builtin.TypeId;

pub const IdLocal = struct {
    str: [191]u8 = .{0} ** 191,
    strlen: u8 = 0,
    hash: u64 = 0,

    pub fn init(id: []const u8) IdLocal {
        var res: IdLocal = undefined;
        res.set(id);
        return res;
    }

    pub fn initFormat(comptime fmt: []const u8, args: anytype) IdLocal {
        var res: IdLocal = undefined;
        const nameslice = std.fmt.bufPrint(res.str[0..res.str.len], fmt, args) catch unreachable;
        res.strlen = @intCast(u8, nameslice.len);
        res.str[res.strlen] = 0;
        res.hash = std.hash.Wyhash.hash(0, res.str[0..res.strlen]);
        return res;
    }

    pub fn id64(id: []const u8) u64 {
        return std.hash.Wyhash.hash(0, id);
    }

    pub fn set(self: *IdLocal, str: []const u8) void {
        if (str[0] == 0) {
            self.*.clear();
            return;
        }
        self.strlen = @intCast(u8, str.len);
        self.hash = std.hash.Wyhash.hash(0, str[0..self.strlen]);
        std.mem.copy(u8, self.str[0..self.str.len], str);
        self.str[self.strlen] = 0;
    }

    pub fn toString(self: IdLocal) []const u8 {
        return self.str[0..self.strlen];
    }

    pub fn toCString(self: IdLocal) [*c]const u8 {
        return @ptrCast([*c]const u8, self.str[0..self.strlen]);
    }

    pub fn debugPrint(self: IdLocal) void {
        std.debug.print("id: {s}:{}:{}\n", .{ self.str[0..self.strlen], self.strlen, self.hash });
    }

    pub fn clear(self: *IdLocal) void {
        self.hash = 0;
        self.strlen = 0;
        std.mem.set(u8, &self.str, 0);
    }

    pub fn isUnset(self: IdLocal) bool {
        return self.hash == 0;
    }

    pub fn eql(self: IdLocal, other: IdLocal) bool {
        return self.hash == other.hash;
    }

    pub fn eqlStr(self: IdLocal, other: []const u8) bool {
        return std.mem.eql(u8, self.str[0..self.strlen], other);
    }
    pub fn eqlHash(self: IdLocal, other: u64) bool {
        return self.hash == other;
    }
};

pub const IdLocalContext = struct {
    pub fn hash(self: @This(), id: IdLocal) u64 {
        _ = self;
        return id.hash;
    }

    pub fn eql(self: @This(), a: IdLocal, b: IdLocal) bool {
        _ = self;
        return a.eql(b);
    }
};

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
            .elem_size = @intCast(u16, @sizeOf(@TypeOf(ptr.*))),
        };
    }

    pub fn createSlice(slice: anytype, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            .value = .{ .ptr_array = slice.ptr },
            .tag = tag,
            .array_count = @intCast(u16, slice.len),
            .elem_size = @intCast(u16, @sizeOf(@TypeOf(slice[0]))),
        };
    }

    pub fn createStringFixed(string: []const u8, tag: Tag) Variant {
        assert(tag != 0);
        return Variant{
            // .value = .{ .ptr_array_const = string.ptr },
            .value = .{ .ptr_array_const = string.ptr },
            .tag = tag,
            .array_count = @intCast(u16, string.len),
            .elem_size = @intCast(u16, @sizeOf(u8)),
        };
    }

    // pub fn createSliceConst(slice: anytype, tag: Tag) Variant {
    //     assert(tag != 0);
    //     return Variant{
    //         .value = .{ .ptr_array = @ptrToInt(slice.ptr) },
    //         .tag = tag,
    //         .count = slice.len,
    //         .elem_size = @intCast(u16, @sizeOf(slice.ptr.*)),
    //     };
    // }

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
        self.value = .{ .ptr_single = ptr };
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
        return @ptrCast(*T, @alignCast(@alignOf(T), self.value.ptr_single));
    }

    pub fn getSlice(self: Variant, comptime T: type, tag: Tag) []T {
        assert(tag == self.tag);
        var ptr = @ptrCast([*]T, @alignCast(@alignOf(T), self.value.ptr_array));
        return ptr[0..self.array_count];
    }

    pub fn getSliceConst(self: Variant, comptime T: type, tag: Tag) []T {
        assert(tag == self.tag);
        var ptr = @ptrCast([*]T, self.value.ptr_array_const);
        return ptr[0..self.array_count];
    }

    pub fn getStringConst(self: Variant, tag: Tag) []const u8 {
        assert(tag == self.tag);
        var ptr = @ptrCast([*]const u8, self.value.ptr_array_const);
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
};
