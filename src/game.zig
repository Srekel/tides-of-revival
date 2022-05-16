const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");

const offline = @import("offline_generation.zig");
const window = @import("window.zig");
const gfx = @import("gfx_wgpu.zig");
const triangle_system = @import("systems/triangle_system.zig");

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
    const main_window = window.createWindow("The Elvengroin Legacy") catch unreachable;

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state);

    // _ = window.createWindow("Debug") catch unreachable;

    var ts = try triangle_system.create(std.heap.page_allocator, &gfx_state);
    defer triangle_system.destroy(&ts);

    var sys = world.newWrappedRunSystem("MoveWrap", .on_update, ComponentData, moveWrapped);
    sys

    while (true) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            break;
        }

        gfx.update(&gfx_state);
        const stats = gfx_state.gctx.stats;
        const dt = @floatCast(f32, stats.delta_time);

        world.progress(dt);
        triangle_system.update(&ts);
        gfx.draw(&gfx_state);
    }
}
