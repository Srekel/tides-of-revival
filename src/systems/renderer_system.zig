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
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");

const terrain_render_pass = @import("renderer_system/terrain_render_pass.zig");
const TerrainRenderPass = terrain_render_pass.TerrainRenderPass;
const geometry_render_pass = @import("renderer_system/geometry_render_pass.zig");
const GeometryRenderPass = geometry_render_pass.GeometryRenderPass;
const deferred_shading_render_pass = @import("renderer_system/deferred_shading_render_pass.zig");
const DeferredShadingRenderPass = deferred_shading_render_pass.DeferredShadingRenderPass;
const skybox_render_pass = @import("renderer_system/skybox_render_pass.zig");
const SkyboxRenderPass = skybox_render_pass.SkyboxRenderPass;
const tonemap_render_pass = @import("renderer_system/tonemap_render_pass.zig");
const TonemapRenderPass = tonemap_render_pass.TonemapRenderPass;
const ui_render_pass = @import("renderer_system/ui_render_pass.zig");
const UIRenderPass = ui_render_pass.UIRenderPass;

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    sys: ecs.entity_t,
    terrain_render_pass: *TerrainRenderPass,
    geometry_render_pass: *GeometryRenderPass,
    deferred_shading_render_pass: *DeferredShadingRenderPass,
    skybox_render_pass: *SkyboxRenderPass,
    tonemap_render_pass: *TonemapRenderPass,
    ui_render_pass: *UIRenderPass,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    const system = ctx.allocator.create(SystemState) catch unreachable;
    const sys = ctx.ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PostUpdate, fd.NOCOMP, update, .{ .ctx = system });

    const geometry_pass = GeometryRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_gbuffer_pass_render_fn = geometry_render_pass.renderFn;
    ctx.renderer.render_gbuffer_pass_render_shadow_map_fn = geometry_render_pass.renderShadowMapFn;
    ctx.renderer.render_gbuffer_pass_prepare_descriptor_sets_fn = geometry_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_unload_descriptor_sets_fn = geometry_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_user_data = geometry_pass;

    const terrain_pass = TerrainRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.world_patch_mgr, ctx.allocator);
    ctx.renderer.render_terrain_pass_render_fn = terrain_render_pass.renderFn;
    ctx.renderer.render_terrain_pass_render_shadow_map_fn = terrain_render_pass.renderShadowMapFn;
    ctx.renderer.render_terrain_pass_prepare_descriptor_sets_fn = terrain_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_terrain_pass_unload_descriptor_sets_fn = terrain_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_terrain_pass_user_data = terrain_pass;

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

    const tonemap_pass = TonemapRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_tonemap_pass_render_fn = tonemap_render_pass.renderFn;
    ctx.renderer.render_tonemap_pass_prepare_descriptor_sets_fn = tonemap_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_tonemap_pass_unload_descriptor_sets_fn = tonemap_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_tonemap_pass_user_data = tonemap_pass;

    const ui_pass = UIRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_ui_pass_render_fn = ui_render_pass.renderFn;
    ctx.renderer.render_ui_pass_prepare_descriptor_sets_fn = ui_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_ui_pass_unload_descriptor_sets_fn = ui_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_ui_pass_user_data = ui_pass;

    system.* = .{
        .allocator = ctx.allocator,
        .ecsu_world = ctx.ecsu_world,
        .renderer = ctx.renderer,
        .terrain_render_pass = terrain_pass,
        .geometry_render_pass = geometry_pass,
        .deferred_shading_render_pass = deferred_shading_pass,
        .skybox_render_pass = skybox_pass,
        .tonemap_render_pass = tonemap_pass,
        .ui_render_pass = ui_pass,
        .sys = sys,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.terrain_render_pass.destroy();
    system.renderer.render_terrain_pass_render_fn = null;
    system.renderer.render_terrain_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_terrain_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_terrain_pass_user_data = null;

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

    system.skybox_render_pass.destroy();
    system.renderer.render_skybox_pass_render_fn = null;
    system.renderer.render_skybox_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_skybox_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_skybox_pass_user_data = null;

    system.tonemap_render_pass.destroy();
    system.renderer.render_tonemap_pass_render_fn = null;
    system.renderer.render_tonemap_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_tonemap_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_tonemap_pass_user_data = null;

    system.ui_render_pass.destroy();
    system.renderer.render_ui_pass_render_fn = null;
    system.renderer.render_ui_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_ui_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_ui_pass_user_data = null;

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
