const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const gfx = @import("../gfx_d3d12.zig");
const renderer_types = @import("../renderer/renderer_types.zig");
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;

const IdLocal = @import("../variant.zig").IdLocal;
const input = @import("../input.zig");
const fd = @import("../flecs_data.zig");

const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: *ecsu.World,
    sys: ecs.entity_t,

    gfx: *gfx.D3D12State,

    point_lights: std.ArrayList(renderer_types.PointLightGPU),
    gpu_frame_profiler_index: u64 = undefined,

    query_directional_lights: ecsu.Query,
    query_point_lights: ecsu.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, ecsu_world: *ecsu.World, _: *input.FrameData) !*SystemState {
    var point_lights = std.ArrayList(renderer_types.PointLightGPU).init(allocator);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PreUpdate, fd.NOCOMP, update, .{ .ctx = state });

    var query_builder_directional_lights = ecsu.QueryBuilder.init(ecsu_world.*);
    _ = query_builder_directional_lights
        .withReadonly(fd.Rotation)
        .withReadonly(fd.DirectionalLight);
    var query_directional_lights = query_builder_directional_lights.buildQuery();

    var query_builder_point_lights = ecsu.QueryBuilder.init(ecsu_world.*);
    _ = query_builder_point_lights
        .withReadonly(fd.Position)
        .withReadonly(fd.PointLight);
    var query_point_lights = query_builder_point_lights.buildQuery();

    state.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .gfx = gfxstate,
        .point_lights = point_lights,
        .query_directional_lights = query_directional_lights,
        .query_point_lights = query_point_lights,
    };

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_directional_lights.deinit();
    state.query_point_lights.deinit();
    state.point_lights.deinit();
    state.allocator.destroy(state);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    var state: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    var entity_iter_directional_lights = state.query_directional_lights.iterator(struct {
        rotation: *const fd.Rotation,
        light: *const fd.DirectionalLight,
    });

    while (entity_iter_directional_lights.next()) |comps| {
        const z_forward = zm.rotate(comps.rotation.asZM(), zm.Vec{0, 0, 1, 0});
        // std.log.debug("Directional light forward: {d:.3}, {d:.3}, {d:.3}\n", .{z_forward[0], z_forward[1], z_forward[2]});

        state.gfx.main_light = renderer_types.DirectionalLightGPU{
            .direction = [3]f32{ -z_forward[0], -z_forward[1], -z_forward[2] },
            .radiance = [3]f32{ comps.light.radiance.r, comps.light.radiance.g, comps.light.radiance.b },
        };
    }


    var entity_iter_point_lights = state.query_point_lights.iterator(struct {
        position: *const fd.Position,
        light: *const fd.PointLight,
    });

    state.point_lights.clearRetainingCapacity();

    while (entity_iter_point_lights.next()) |comps| {
        // TODO(gmodarelli): Implement frustum culling
        const point_light = renderer_types.PointLightGPU{
            .position = [3]f32{ comps.position.x, comps.position.y, comps.position.z },
            .radiance = [3]f32{ comps.light.radiance.r, comps.light.radiance.g, comps.light.radiance.b },
            .radius = comps.light.radius,
            .falloff = comps.light.falloff,
            .max_intensity = comps.light.max_intensity,
        };

        state.point_lights.append(point_light) catch unreachable;
    }

    if (state.point_lights.items.len > 0) {
        const frame_index = state.gfx.gctx.frame_index;
        _ = state.gfx.uploadDataToBuffer(renderer_types.PointLightGPU, state.gfx.point_lights_buffers[frame_index], 0, state.point_lights.items);
        state.gfx.num_point_lights[frame_index] = @as(u32, @intCast(state.point_lights.items.len));
    }
}