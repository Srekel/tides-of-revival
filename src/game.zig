const std = @import("std");
const args = @import("args");
const flecs = @import("flecs");
const RndGen = std.rand.DefaultPrng;

const window = @import("window.zig");
const gfx = @import("gfx_wgpu.zig");
const camera_system = @import("systems/camera_system.zig");
const gui_system = @import("systems/gui_system.zig");
const physics_system = @import("systems/physics_system.zig");
const procmesh_system = @import("systems/procedural_mesh_system.zig");
const terrain_system = @import("systems/terrain_system.zig");
const triangle_system = @import("systems/triangle_system.zig");
const fd = @import("flecs_data.zig");
const IdLocal = @import("variant.zig").IdLocal;

pub fn run() void {
    var flecs_world = flecs.World.init();
    defer flecs_world.deinit();

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("The Elvengroin Legacy") catch unreachable;

    var gfx_state = gfx.init(std.heap.page_allocator, main_window) catch unreachable;
    defer gfx.deinit(&gfx_state);

    var physics_sys = try physics_system.create(
        IdLocal.init("physics_system_{}"),
        std.heap.page_allocator,
        &flecs_world,
    );
    defer physics_system.destroy(physics_sys);

    var camera_sys = try camera_system.create(
        IdLocal.init("camera_system"),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
        physics_sys.physics_world,
    );
    defer camera_system.destroy(camera_sys);

    // var triangle_sys = try triangle_system.create(IdLocal.initFormat("triangle_system_{}", .{0}), std.heap.page_allocator, &gfx_state, &flecs_world);
    // defer triangle_system.destroy(triangle_sys);
    // var ts2 = try triangle_system.create(IdLocal.initFormat("triangle_system_{}", .{1}), std.heap.page_allocator, &gfx_state, &flecs_world);
    // defer triangle_system.destroy(ts2);

    var procmesh_sys = try procmesh_system.create(
        IdLocal.initFormat("procmesh_system_{}", .{0}),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
    );
    defer procmesh_system.destroy(procmesh_sys);

    var terrain_sys = try terrain_system.create(
        IdLocal.init("terrain_system"),
        std.heap.page_allocator,
        &gfx_state,
        &flecs_world,
        physics_sys.physics_world,
    );
    defer terrain_system.destroy(terrain_sys);

    var gui_sys = try gui_system.create(
        std.heap.page_allocator,
        &gfx_state,
        main_window,
    );
    defer gui_system.destroy(&gui_sys);

    // const entity1 = flecs_world.newEntity();
    // entity1.set(fd.Position{ .x = -1, .y = 0, .z = 0 });
    // entity1.set(fd.Scale{});
    // entity1.set(fd.Velocity{ .x = 10, .y = 0, .z = 0 });
    // entity1.set(fd.CIShapeMeshInstance{
    //     .id = IdLocal.id64("sphere"),
    //     .basecolor_roughness = .{ .r = 0.1, .g = 1.0, .b = 0.0, .roughness = 0.1 },
    // });

    // const entity2 = flecs_world.newEntity();
    // entity2.set(fd.Position{ .x = 1, .y = 0, .z = 0 });
    // entity2.set(fd.Velocity{ .x = 0, .y = 1, .z = 0 });

    const entity3 = flecs_world.newEntity();
    entity3.set(fd.Transform.init(3.4, 10, 0.6));
    entity3.set(fd.Scale.createScalar(0.5));
    // entity3.set(fd.Velocity{ .x = -10, .y = 0, .z = 0 });
    entity3.set(fd.CIShapeMeshInstance{
        .id = IdLocal.id64("sphere"),
        .basecolor_roughness = .{ .r = 0.7, .g = 0.0, .b = 1.0, .roughness = 0.8 },
    });
    entity3.set(fd.CIPhysicsBody{
        .shape_type = .sphere,
        .mass = 1,
        .sphere = .{ .radius = 0.5 },
    });

    if (false) {
        var rnd = RndGen.init(0);
        var x: f32 = -1;
        while (x < 20) : (x += 1) {
            var z: f32 = -1;
            while (z < 20) : (z += 1) {
                const scale = 0.5 + rnd.random().float(f32) * 5;
                const entity = flecs_world.newEntity();
                entity.set(fd.Transform.init(
                    x * 1.5 + rnd.random().float(f32) * 0.5,
                    0 * 1.5 + rnd.random().float(f32) * 1 + 0.5 - scale + @sin(x * 0.4) + @cos(z * 0.25),
                    z * 1.5 + rnd.random().float(f32) * 0.5,
                ));
                entity.set(fd.Scale.createScalar(scale));
                entity.set(fd.CIShapeMeshInstance{
                    .id = IdLocal.id64("sphere"),
                    .basecolor_roughness = .{
                        .r = 0.1 + rnd.random().float(f32) * 0.3,
                        .g = 0.3 + rnd.random().float(f32) * 0.5,
                        .b = 0.1 + rnd.random().float(f32) * 0.1,
                        .roughness = 1.0,
                    },
                });
                entity.set(fd.CIPhysicsBody{
                    .shape_type = .sphere,
                    .mass = 0,
                    .sphere = .{ .radius = scale },
                });
            }
        }
    }

    const camera_ent = flecs_world.newEntity();
    camera_ent.set(fd.Position{ .x = 0, .y = 2, .z = -30 });
    camera_ent.set(fd.CICamera{
        .lookat = .{ .x = 0, .y = 1, .z = 30 },
        .near = 0.1,
        .far = 10000,
        .window = main_window,
    });
    camera_ent.set(fd.WorldLoader{
        .range = 2,
    });

    while (true) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            break;
        }

        const stats = gfx_state.gctx.stats;
        const dt = @floatCast(f32, stats.delta_time);
        gfx.update(&gfx_state);
        gui_system.preUpdate(&gui_sys);

        flecs_world.progress(dt);
        gui_system.update(&gui_sys);
        gfx.draw(&gfx_state);
    }
}
