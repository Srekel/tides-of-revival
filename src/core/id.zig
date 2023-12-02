const std = @import("std");

pub const ID = IdLocal.init;

pub const IdLocal = struct {
    str: [191]u8 = .{0} ** 191,
    strlen: u8 = 0,
    hash: u64 = 0,

    pub fn init(id: []const u8) IdLocal {
        std.debug.assert(id.len < 190);
        var res: IdLocal = undefined;
        res.set(id);
        res.str[id.len] = 0;
        return res;
    }

    pub fn initFormat(comptime fmt: []const u8, args: anytype) IdLocal {
        var res: IdLocal = undefined;
        const nameslice = std.fmt.bufPrint(res.str[0..res.str.len], fmt, args) catch unreachable;
        std.debug.assert(nameslice.len < 190);
        res.strlen = @as(u8, @intCast(nameslice.len));
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
        self.strlen = @as(u8, @intCast(str.len));
        self.hash = std.hash.Wyhash.hash(0, str[0..self.strlen]);
        std.mem.copy(u8, self.str[0..self.str.len], str);
        self.str[self.strlen] = 0;
    }

    pub fn toString(self: *const IdLocal) []const u8 {
        return self.str[0..self.strlen];
    }

    pub fn toCString(self: *const IdLocal) [:0]const u8 {
        return @ptrCast(self.str[0..self.strlen]);
    }

    pub fn debugPrint(self: IdLocal) void {
        std.debug.print("id: {s}:{}:{}\n", .{ self.str[0..self.strlen], self.strlen, self.hash });
    }

    pub fn clear(self: *IdLocal) void {
        self.hash = 0;
        self.strlen = 0;
        @memset(self.str[0..], 0);
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

pub const IdLocalHashMapContext = struct {
    pub fn hash(self: @This(), id: IdLocal) u64 {
        _ = self;
        return id.hash;
    }

    pub fn eql(self: @This(), a: IdLocal, b: IdLocal) bool {
        _ = self;
        return a.eql(b);
    }
};
