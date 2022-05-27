const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");

const window = @import("window.zig");
const gfx = @import("gfx_wgpu.zig");
const camera_system = @import("systems/camera_system.zig");
const procmesh_system = @import("systems/procedural_mesh_system.zig");
const triangle_system = @import("systems/triangle_system.zig");
const gui_system = @import("systems/gui_system.zig");
const fd = @import("flecs_data.zig");
const IdLocal = @import("variant.zig").IdLocal;

pub fn run() void {
    var world = flecs.World.init();
    defer world.deinit();

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("The Elvengroin Legacy") catch unreachable;

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state);

    var camera_sys = try camera_system.create(IdLocal.init("camera_system"), std.heap.page_allocator, &gfx_state, &world);
    defer camera_system.destroy(camera_sys);
    var triangle_sys = try triangle_system.create(IdLocal.initFormat("triangle_system_{}", .{0}), std.heap.page_allocator, &gfx_state, &world);
    defer triangle_system.destroy(triangle_sys);
    // var ts2 = try triangle_system.create(IdLocal.initFormat("triangle_system_{}", .{1}), std.heap.page_allocator, &gfx_state, &world);
    // defer triangle_system.destroy(ts2);
    var procmesh_sys = try procmesh_system.create(IdLocal.initFormat("procmesh_system_{}", .{0}), std.heap.page_allocator, &gfx_state, &world);
    defer procmesh_system.destroy(procmesh_sys);
    var gui_sys = try gui_system.create(std.heap.page_allocator, &gfx_state, main_window);
    defer gui_system.destroy(&gui_sys);

    const entity1 = world.newEntity();
    entity1.set(fd.Position{ .x = -1, .y = 1, .z = 0 });
    entity1.set(fd.Velocity{ .x = 10, .y = 0.1, .z = 0 });
    entity1.set(fd.CIMesh{
        .mesh_type = 0,
        .basecolor_roughness = .{ .r = 0.1, .g = 1.0, .b = 0.0, .roughness = 0.1 },
    });
    const entity2 = world.newEntity();
    entity2.set(fd.Position{ .x = 1, .y = 0, .z = 0 });
    entity2.set(fd.Velocity{ .x = 0, .y = 1, .z = 0 });
    const entity3 = world.newEntity();
    entity3.set(fd.Position{ .x = 3, .y = 1, .z = 0 });
    entity3.set(fd.CIMesh{
        .mesh_type = 0,
        .basecolor_roughness = .{ .r = 0.7, .g = 0.0, .b = 1.0, .roughness = 0.8 },
    });
    entity3.set(fd.Velocity{ .x = -10, .y = 1, .z = 0 });

    const camera_ent = world.newEntity();
    camera_ent.set(fd.Position{ .x = 0, .y = 0, .z = 0 });
    camera_ent.set(fd.CICamera{
        .lookat = .{ .x = 0, .y = 0, .z = 0 },
        .near = 0.1,
        .far = 1000,
        .window = main_window,
    });

    while (true) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            break;
        }

        gfx.update(&gfx_state);
        gui_system.preUpdate(&gui_sys);
        const stats = gfx_state.gctx.stats;
        const dt = @floatCast(f32, stats.delta_time);

        world.progress(dt);
        gui_system.update(&gui_sys);
        gfx.draw(&gfx_state);
    }
}
