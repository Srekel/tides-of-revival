const std = @import("std");

fn simulate() callconv(.C) void {
    std.log.debug("hi", .{});
}

pub const SimulatorAPI = extern struct {
    simulate: *const fn () callconv(.C) void,
};

pub fn getAPI() callconv(.C) SimulatorAPI {
    return SimulatorAPI{
        .simulate = simulate,
    };
}
