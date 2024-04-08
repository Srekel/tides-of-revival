const std = @import("std");

pub const GameObjectID = u64;

pub const AudioManager = struct {
    pub fn create(allocator: std.mem.Allocator) !AudioManager {
        _ = allocator; // autofix
        return .{};
    }

    pub fn init(self: *AudioManager) !void {
        _ = self; // autofix
    }

    pub fn destroy(self: *AudioManager) !void {
        _ = self; // autofix
    }
};
