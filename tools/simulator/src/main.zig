const std = @import("std");
const args = @import("args");

const sim_api = @import("sim/api.zig");
const Simulator = @import("sim/simulator.zig").Simulator;

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

    const api = sim_api.getAPI();
    var simulator = Simulator{};
    simulator.init();
    defer simulator.deinit();
    sim_api.simulator = &simulator;

    if (options.options.generate) {
        //
    } else {
        var dll_ui = std.DynLib.open("ui.dll") catch unreachable;
        const dll_ui_runUI = dll_ui.lookup(c_ui.PFN_runUI, "runUI").?.?;
        const dll_ui_compute = dll_ui.lookup(c_ui.PFN_compute, "compute").?.?;
        simulator.ctx.compute_fn = @ptrCast(dll_ui_compute);

        dll_ui_runUI(@ptrCast(&api));

        std.log.debug("{any}", .{dll_ui});
        std.log.debug("{any}", .{dll_ui_runUI});
    }
}
