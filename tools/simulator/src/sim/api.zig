const std = @import("std");
const Simulator = @import("simulator.zig").Simulator;

const c_self_api = @cImport({
    @cInclude("api.h");
});

pub var simulator: *Simulator = undefined;

fn simulate() callconv(.C) void {
    simulator.simulate();
}

fn simulateSteps(steps: c_uint) callconv(.C) void {
    simulator.simulateSteps(steps);
}

fn getPreview(resource_name: [*c]u8, image_width: c_uint, image_height: c_uint) callconv(.C) [*c]const u8 {
    const preview = simulator.getPreview(std.mem.span(resource_name), image_width, image_height);
    return @ptrCast(preview);
}

fn getProgress() callconv(.C) c_self_api.SimulatorProgress {
    const progress = simulator.getProgress();
    return .{
        .percent = progress.percent,
    };
}

pub const SimulatorAPI = extern struct {
    simulate: *const fn () callconv(.C) void,
    simulateSteps: *const fn (steps: c_uint) callconv(.C) void,
    getPreview: *const fn (resource_name: [*c]u8, image_width: c_uint, image_height: c_uint) callconv(.C) [*c]const u8,
    getProgress: *const fn () callconv(.C) c_self_api.SimulatorProgress,
    // abort: *const fn () callconv(.C) void,
};

pub fn getAPI() callconv(.C) SimulatorAPI {
    return SimulatorAPI{
        .simulate = simulate,
        .simulateSteps = simulateSteps,
        .getPreview = getPreview,
        .getProgress = getProgress,
    };
}
