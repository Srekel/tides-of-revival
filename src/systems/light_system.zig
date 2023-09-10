const std = @import("std");
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const zm = @import("zmath");
const zmu = @import("zmathutil");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");

const gfx = @import("../gfx_d3d12.zig");
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

    lights: std.ArrayList(fd.Light),
    gpu_frame_profiler_index: u64 = undefined,

    query_lights: ecsu.Query,
};

pub fn create(name: IdLocal, allocator: std.mem.Allocator, gfxstate: *gfx.D3D12State, ecsu_world: *ecsu.World, _: *input.FrameData) !*SystemState {
    var lights = std.ArrayList(fd.Light).init(allocator);

    var state = allocator.create(SystemState) catch unreachable;
    var sys = ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PreUpdate, fd.NOCOMP, update, .{ .ctx = state });

    var query_builder_lights = ecsu.QueryBuilder.init(ecsu_world.*);
    _ = query_builder_lights
        .withReadonly(fd.Rotation)
        .withReadonly(fd.Light);
    var query_lights = query_builder_lights.buildQuery();

    state.* = .{
        .allocator = allocator,
        .ecsu_world = ecsu_world,
        .sys = sys,
        .gfx = gfxstate,
        .lights = lights,
        .query_lights = query_lights,
    };

    return state;
}

pub fn destroy(state: *SystemState) void {
    state.query_lights.deinit();
    state.lights.deinit();
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

    var entity_iter_lights = state.query_lights.iterator(struct {
        rotation: *const fd.Rotation,
        light: *const fd.Light,
    });

    state.lights.clearRetainingCapacity();

    while (entity_iter_lights.next()) |comps| {
        // Directional lights
        if (comps.light.light_type == 0) {
            const z_forward = zm.rotate(comps.rotation.asZM(), zm.Vec{0, 0, 1, 0});
            // std.log.debug("Directional light forward: {d:.3}, {d:.3}, {d:.3}\n", .{z_forward[0], z_forward[1], z_forward[2]});

            const directional_light = fd.Light{
                .position = [3]f32{ -z_forward[0], -z_forward[1], -z_forward[2] },
                .radiance = comps.light.radiance,
                .range = comps.light.range,
                .light_type = comps.light.light_type,
            };

            state.lights.append(directional_light) catch unreachable;
        }
    }

    if (state.lights.items.len > 0) {
        const frame_index = state.gfx.gctx.frame_index;
        _ = state.gfx.uploadDataToBuffer(fd.Light, state.gfx.lights_buffers[frame_index], 0, state.lights.items);
    }
}