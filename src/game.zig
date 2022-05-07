const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");

const offline = @import("offline_generation.zig");
const window = @import("window.zig");

// pub const Velocity = struct { x: f32, y: f32 };
// pub const Position = struct { x: f32, y: f32 };
// pub const Acceleration = struct { x: f32, y: f32 };

// const ComponentData = struct { pos: *Position, vel: *Velocity };
// const AccelComponentData = struct { pos: *Position, vel: *Velocity, accel: *Acceleration };

pub fn run() void {
    var world = flecs.World.init();
    defer world.deinit();

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    _ = window.createWindow("The Elvengroin Legacy") catch unreachable;
    // _ = window.createWindow("Debug") catch unreachable;

    while (true) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            break;
        }
    }
}
