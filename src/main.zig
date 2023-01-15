const std = @import("std");
const args = @import("args");
const offline = @import("offline_generation/main.zig");
const game = @import("game.zig");

pub fn main() void {
    const options = args.parseForCurrentProcess(struct {
        // This declares long options for double hyphen
        @"offlinegen": bool = false,
        // output: ?[]const u8 = null,
        // @"with-offset": bool = false,
        // @"with-hexdump": bool = false,
        // @"intermix-source": bool = false,
        // numberOfBytes: ?i32 = null,
        // signed_number: ?i64 = null,
        // unsigned_number: ?u64 = null,
        // mode: enum { default, special, slow, fast } = .default,

        // This declares short-hand options for single hyphen
        pub const shorthands = .{
            .g = "offlinegen",
            // .b = "with-hexdump",
            // .O = "with-offset",
            // .o = "output",
        };
    }, std.heap.page_allocator, .print) catch unreachable;
    defer options.deinit();

    if (options.options.@"offlinegen") {
        offline.generate();
    } else {
        game.run();
    }
}
