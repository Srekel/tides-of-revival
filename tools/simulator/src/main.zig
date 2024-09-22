const std = @import("std");
const args = @import("args");

const sim_api = @import("sim/api.zig");

const c_ui = @cImport({
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
        var dll_ui = std.DynLib.open("ui.dll") catch unreachable;
        const dll_ui_runUI = dll_ui.lookup(c_ui.PFN_runUI, "runUI").?.?;

        const api = sim_api.getAPI();
        dll_ui_runUI(@ptrCast(&api));

        std.log.debug("{any}", .{dll_ui});
        std.log.debug("{any}", .{dll_ui_runUI});
    }
}
