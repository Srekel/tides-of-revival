const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const gfx = @import("../renderer/gfx_d3d12.zig");
const renderer_types = @import("../renderer/renderer_types.zig");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;

const IdLocal = @import("../core/core.zig").IdLocal;
const input = @import("../input.zig");
const fd = @import("../config/flecs_data.zig");

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    sys: ecs.entity_t,

    gfx: *gfx.D3D12State,

    point_lights: std.ArrayList(renderer_types.PointLightGPU),
    gpu_frame_profiler_index: u64 = undefined,

    query_directional_lights: ecsu.Query,
    query_point_lights: ecsu.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, ecsu_world: ecsu.World, _: *input.FrameData) !*SystemState {
    const point_lights = std.ArrayList(renderer_types.PointLightGPU).init(allocator);

    const system = allocator.create(SystemState) catch unreachable;
    const sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PreUpdate, fd.NOCOMP, update, .{ .ctx = system });

    var query_builder_directional_lights = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_directional_lights
        .withReadonly(fd.Rotation)
        .withReadonly(fd.DirectionalLight);
    const query_directional_lights = query_builder_directional_lights.buildQuery();

    var query_builder_point_lights = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_point_lights
        .withReadonly(fd.Transform)
        .withReadonly(fd.PointLight);
    const query_point_lights = query_builder_point_lights.buildQuery();

    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .gfx = gfxstate,
        .point_lights = point_lights,
        .query_directional_lights = query_directional_lights,
        .query_point_lights = query_point_lights,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.query_directional_lights.deinit();
    system.query_point_lights.deinit();
    system.point_lights.deinit();
    system.allocator.destroy(system);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    var system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    var entity_iter_directional_lights = system.query_directional_lights.iterator(struct {
        rotation: *const fd.Rotation,
        light: *const fd.DirectionalLight,
    });

    while (entity_iter_directional_lights.next()) |comps| {
        const z_forward = zm.rotate(comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 });

        system.gfx.main_light = renderer_types.DirectionalLightGPU{
            .direction = [3]f32{ -z_forward[0], -z_forward[1], -z_forward[2] },
            .color = [3]f32{ comps.light.color.r, comps.light.color.g, comps.light.color.b },
            .intensity = comps.light.intensity,
        };
    }

    var entity_iter_point_lights = system.query_point_lights.iterator(struct {
        transform: *const fd.Transform,
        light: *const fd.PointLight,
    });

    system.point_lights.clearRetainingCapacity();

    while (entity_iter_point_lights.next()) |comps| {
        // TODO(gmodarelli): Implement frustum culling
        const point_light = renderer_types.PointLightGPU{
            .position = comps.transform.getPos00(),
            .range = comps.light.range,
            .color = [3]f32{ comps.light.color.r, comps.light.color.g, comps.light.color.b },
            .intensity = comps.light.intensity,
        };

        system.point_lights.append(point_light) catch unreachable;
    }

    if (system.point_lights.items.len > 0) {
        const frame_index = system.gfx.gctx.frame_index;
        _ = system.gfx.uploadDataToBuffer(renderer_types.PointLightGPU, system.gfx.point_lights_buffers[frame_index], 0, system.point_lights.items);
        system.gfx.point_lights_count[frame_index] = @intCast(system.point_lights.items.len);
    }
}
