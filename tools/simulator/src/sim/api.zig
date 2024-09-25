const std = @import("std");
const Simulator = @import("simulator.zig").Simulator;

pub var simulator: *Simulator = undefined;

fn simulate() callconv(.C) void {
    simulator.simulate();
}

fn simulateSteps(steps: c_uint) callconv(.C) void {
    simulator.simulateSteps(steps);
}

fn get_preview(image_width: c_uint, image_height: c_uint) callconv(.C) [*c]u8 {
    return simulator.get_preview(image_width, image_height);
}

pub const SimulatorAPI = extern struct {
    simulate: *const fn () callconv(.C) void,
    simulateSteps: *const fn (steps: c_uint) callconv(.C) void,
    get_preview: *const fn (image_width: c_uint, image_height: c_uint) callconv(.C) [*c]u8,
    // getCurrentProgress: *const fn () callconv(.C) void,
    // abort: *const fn () callconv(.C) void,
};

pub fn getAPI() callconv(.C) SimulatorAPI {
    return SimulatorAPI{
        .simulate = simulate,
        .simulateSteps = simulateSteps,
        .get_preview = get_preview,
    };
}
