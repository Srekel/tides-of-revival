const std = @import("std");

const context = @import("../core/context.zig");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const renderer = @import("../renderer/renderer.zig");
const zforge = @import("zforge");
const util = @import("../util.zig");
const zm = @import("zmath");
const geometry_render_pass = @import("renderer_system/geometry_render_pass.zig");
const GeometryRenderPass = geometry_render_pass.GeometryRenderPass;

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    sys: ecs.entity_t,
    uniform_frame_data: renderer.CameraUniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    geometry_render_pass: *GeometryRenderPass,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    const system = ctx.allocator.create(SystemState) catch unreachable;
    const sys = ctx.ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PostUpdate, fd.NOCOMP, update, .{ .ctx = system });

    const uniform_frame_buffers = blk: {
        var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
        for (buffers, 0..) |_, buffer_index| {
            buffers[buffer_index] = ctx.renderer.createUniformBuffer(renderer.CameraUniformFrameData);
        }

        break :blk buffers;
    };

    const pass = GeometryRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_gbuffer_pass_render_fn = geometry_render_pass.renderFn;
    ctx.renderer.render_gbuffer_pass_prepare_descriptor_sets_fn = geometry_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_user_data = pass;

    system.* = .{
        .allocator = ctx.allocator,
        .ecsu_world = ctx.ecsu_world,
        .renderer = ctx.renderer,
        .geometry_render_pass = pass,
        .sys = sys,
        .uniform_frame_data = std.mem.zeroes(renderer.CameraUniformFrameData),
        .uniform_frame_buffers = uniform_frame_buffers,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.geometry_render_pass.destroy();
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
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    var rctx = system.renderer;

    if (rctx.window.frame_buffer_size[0] != rctx.window_width or rctx.window.frame_buffer_size[1] != rctx.window_height) {
        rctx.window_width = rctx.window.frame_buffer_size[0];
        rctx.window_height = rctx.window.frame_buffer_size[1];

        const reload_desc = graphics.ReloadDesc{ .mType = .{ .RESIZE = true } };
        rctx.onUnload(reload_desc);
        rctx.onLoad(reload_desc) catch unreachable;
    }

    const camera_ent = util.getActiveCameraEnt(system.ecsu_world);
    const camera_component = camera_ent.get(fd.Camera).?;
    const camera_transform = camera_ent.get(fd.Transform).?;
    const camera_position = camera_transform.getPos00();
    const z_view = zm.loadMat(camera_component.view[0..]);
    const z_proj = zm.loadMat(camera_component.projection[0..]);
    const z_proj_view = zm.mul(z_proj, z_view);

    zm.storeMat(&system.uniform_frame_data.projection_view, z_proj_view);
    zm.storeMat(&system.uniform_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
    system.uniform_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };

    rctx.draw();
}

// ██████╗ ██████╗  █████╗ ██╗    ██╗
// ██╔══██╗██╔══██╗██╔══██╗██║    ██║
// ██║  ██║██████╔╝███████║██║ █╗ ██║
// ██║  ██║██╔══██╗██╔══██║██║███╗██║
// ██████╔╝██║  ██║██║  ██║╚███╔███╔╝
// ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝

fn draw(rctx: *renderer.Renderer) void {
    rctx.draw();
}
