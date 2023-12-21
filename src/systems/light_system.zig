const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const renderer_types = @import("../renderer/renderer_types.zig");
const renderer = @import("../renderer/tides_renderer.zig");

const IdLocal = @import("../core/core.zig").IdLocal;
const input = @import("../input.zig");
const fd = @import("../config/flecs_data.zig");

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    sys: ecs.entity_t,

    directional_lights: std.ArrayList(renderer.DirectionalLight),
    point_lights: std.ArrayList(renderer.PointLight),
    directional_lights_buffers: [renderer.buffered_frames_count]renderer.BufferHandle,
    point_lights_buffers: [renderer.buffered_frames_count]renderer.BufferHandle,
    lights_buffer_indices: *renderer.HackyLightBuffersIndices,

    query_directional_lights: ecsu.Query,
    query_point_lights: ecsu.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, ecsu_world: ecsu.World, lights_buffer_indices: *renderer.HackyLightBuffersIndices) !*SystemState {
    var point_lights = std.ArrayList(renderer.PointLight).init(allocator);
    var directional_lights = std.ArrayList(renderer.DirectionalLight).init(allocator);

    var system = allocator.create(SystemState) catch unreachable;
    var sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PreUpdate, fd.NOCOMP, update, .{ .ctx = system });

    var query_builder_directional_lights = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_directional_lights
        .withReadonly(fd.Rotation)
        .withReadonly(fd.DirectionalLight);
    var query_directional_lights = query_builder_directional_lights.buildQuery();

    var query_builder_point_lights = ecsu.QueryBuilder.init(ecsu_world);
    _ = query_builder_point_lights
        .withReadonly(fd.Transform)
        .withReadonly(fd.PointLight);
    var query_point_lights = query_builder_point_lights.buildQuery();

    const directional_lights_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = renderer.directional_lights_count_max * @sizeOf(renderer.DirectionalLight),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(renderer.DirectionalLight), "Directional Lights Buffer");
        }

        break :blk buffers;
    };

    const point_lights_buffers = blk: {
        var buffers: [renderer.buffered_frames_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            const buffer_data = renderer.Slice{
                .data = null,
                .size = renderer.point_lights_count_max * @sizeOf(renderer.PointLight),
            };
            buffers[buffer_index] = renderer.createBuffer(buffer_data, @sizeOf(renderer.PointLight), "Point Lights Buffer");
        }

        break :blk buffers;
    };

    system.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .directional_lights = directional_lights,
        .point_lights = point_lights,
        .directional_lights_buffers = directional_lights_buffers,
        .point_lights_buffers = point_lights_buffers,
        .query_directional_lights = query_directional_lights,
        .query_point_lights = query_point_lights,
        .lights_buffer_indices = lights_buffer_indices,
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

    const frame_index = renderer.frameIndex();

    var entity_iter_directional_lights = system.query_directional_lights.iterator(struct {
        rotation: *const fd.Rotation,
        light: *const fd.DirectionalLight,
    });

    system.directional_lights.clearRetainingCapacity();

    while (entity_iter_directional_lights.next()) |comps| {
        const z_forward = zm.rotate(comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 });
        // TODO(gmodarelli): Specify data for shadow mapping
        const directional_light = renderer.DirectionalLight{
            .direction = [3]f32{ -z_forward[0], -z_forward[1], -z_forward[2] },
            .shadow_map = 0,
            .color = [3]f32{ comps.light.color.r, comps.light.color.g, comps.light.color.b },
            .intensity = comps.light.intensity,
            .shadow_range = 0.0,
            ._pad = [2]f32{ 42, 42 },
            .shadow_map_dimensions = 0,
            .view_proj = [16]f32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        };
        system.directional_lights.append(directional_light) catch unreachable;
    }

    var entity_iter_point_lights = system.query_point_lights.iterator(struct {
        transform: *const fd.Transform,
        light: *const fd.PointLight,
    });

    system.point_lights.clearRetainingCapacity();

    while (entity_iter_point_lights.next()) |comps| {
        const point_light = renderer.PointLight{
            .position = comps.transform.getPos00(),
            .radius = comps.light.range,
            .color = [3]f32{ comps.light.color.r, comps.light.color.g, comps.light.color.b },
            .intensity = comps.light.intensity,
        };

        system.point_lights.append(point_light) catch unreachable;
    }

    if (system.directional_lights.items.len > 0) {
        var directional_lights_slice = renderer.Slice{
            .data = @ptrCast(system.directional_lights.items),
            .size = system.directional_lights.items.len * @sizeOf(renderer.DirectionalLight),
        };
        renderer.updateBuffer(directional_lights_slice, system.directional_lights_buffers[frame_index]);
    }

    if (system.point_lights.items.len > 0) {
        var point_lights_slice = renderer.Slice{
            .data = @ptrCast(system.point_lights.items),
            .size = system.point_lights.items.len * @sizeOf(renderer.PointLight),
        };
        renderer.updateBuffer(point_lights_slice, system.point_lights_buffers[frame_index]);
    }

    system.lights_buffer_indices.* = .{
        .directional_lights_buffer_index = renderer.bufferBindlessIndex(system.directional_lights_buffers[frame_index]),
        .point_lights_buffer_index = renderer.bufferBindlessIndex(system.point_lights_buffers[frame_index]),
        .directional_lights_count = @intCast(system.directional_lights.items.len),
        .point_lights_count = @intCast(system.point_lights.items.len),
    };
}
