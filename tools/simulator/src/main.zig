const std = @import("std");
const args = @import("args");

const c = @cImport({
    @cInclude("main_cpp.h");
});

pub fn main() void {
    const options = args.parseForCurrentProcess(struct {
        generate: bool = false,
        pub const shorthands = .{
            .g = "generate",
        };
    }, std.heap.page_allocator, .print) catch unreachable;
    defer options.deinit();

    if (options.options.generate) {
        //
    } else {
        _ = c.main_cpp();
        // const world = load_world();
        // world.simulate();
    }
}
