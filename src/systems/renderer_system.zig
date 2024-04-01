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
const deferred_shading_render_pass = @import("renderer_system/deferred_shading_render_pass.zig");
const DeferredShadingRenderPass = deferred_shading_render_pass.DeferredShadingRenderPass;
const skybox_render_pass = @import("renderer_system/skybox_render_pass.zig");
const SkyboxRenderPass = skybox_render_pass.SkyboxRenderPass;

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    sys: ecs.entity_t,
    geometry_render_pass: *GeometryRenderPass,
    deferred_shading_render_pass: *DeferredShadingRenderPass,
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

    const geometry_pass = GeometryRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_gbuffer_pass_render_fn = geometry_render_pass.renderFn;
    ctx.renderer.render_gbuffer_pass_prepare_descriptor_sets_fn = geometry_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_unload_descriptor_sets_fn = geometry_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_user_data = geometry_pass;

    const deferred_shading_pass = DeferredShadingRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_deferred_shading_pass_render_fn = deferred_shading_render_pass.renderFn;
    ctx.renderer.render_deferred_shading_pass_prepare_descriptor_sets_fn = deferred_shading_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_deferred_shading_pass_unload_descriptor_sets_fn = deferred_shading_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_deferred_shading_pass_user_data = deferred_shading_pass;

    const skybox_pass = SkyboxRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_skybox_pass_render_fn = skybox_render_pass.renderFn;
    ctx.renderer.render_skybox_pass_prepare_descriptor_sets_fn = skybox_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_skybox_pass_unload_descriptor_sets_fn = skybox_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_skybox_pass_user_data = skybox_pass;

    system.* = .{
        .allocator = ctx.allocator,
        .ecsu_world = ctx.ecsu_world,
        .renderer = ctx.renderer,
        .geometry_render_pass = geometry_pass,
        .deferred_shading_render_pass = deferred_shading_pass,
        .sys = sys,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.geometry_render_pass.destroy();
    system.renderer.render_gbuffer_pass_render_fn = null;
    system.renderer.render_gbuffer_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_gbuffer_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_gbuffer_pass_user_data = null;

    system.deferred_shading_render_pass.destroy();
    system.renderer.render_deferred_shading_pass_render_fn = null;
    system.renderer.render_deferred_shading_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_deferred_shading_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_deferred_shading_pass_user_data = null;

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
        rctx.requestReload(reload_desc);
    }

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
