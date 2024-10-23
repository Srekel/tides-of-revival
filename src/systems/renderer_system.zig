const std = @import("std");

const config = @import("../config/config.zig");
const context = @import("../core/context.zig");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const im3d = @import("im3d");
const input = @import("../input.zig");
const PrefabManager = @import("../prefab_manager.zig").PrefabManager;
const renderer = @import("../renderer/renderer.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../util.zig");
const zm = @import("zmath");
const zgui = @import("zgui");
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
const im3d_render_pass = @import("renderer_system/im3d_render_pass.zig");
const Im3dRenderPass = im3d_render_pass.Im3dRenderPass;

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    pre_sys: ecs.entity_t,
    post_sys: ecs.entity_t,
    terrain_render_pass: *TerrainRenderPass,
    geometry_render_pass: *GeometryRenderPass,
    deferred_shading_render_pass: *DeferredShadingRenderPass,
    skybox_render_pass: *SkyboxRenderPass,
    tonemap_render_pass: *TonemapRenderPass,
    ui_render_pass: *UIRenderPass,
    im3d_render_pass: *Im3dRenderPass,
    render_imgui: bool,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    prefab_mgr: *PrefabManager,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    _ = name;
    const system = ctx.allocator.create(SystemState) catch unreachable;
    const pre_sys = ctx.ecsu_world.newWrappedRunSystem("Render System PreUpdate", ecs.PreUpdate, fd.NOCOMP, preUpdate, .{ .ctx = system });
    const post_sys = ctx.ecsu_world.newWrappedRunSystem("Render System PostUpdate", ecs.PostUpdate, fd.NOCOMP, postUpdate, .{ .ctx = system });

    const geometry_pass = GeometryRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.prefab_mgr, ctx.allocator);
    ctx.renderer.render_gbuffer_pass_render_fn = geometry_render_pass.renderFn;
    ctx.renderer.render_gbuffer_pass_render_shadow_map_fn = geometry_render_pass.renderShadowMapFn;
    ctx.renderer.render_gbuffer_pass_create_descriptor_sets_fn = geometry_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_prepare_descriptor_sets_fn = geometry_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_unload_descriptor_sets_fn = geometry_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_gbuffer_pass_user_data = geometry_pass;

    const terrain_pass = TerrainRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.world_patch_mgr, ctx.allocator);
    ctx.renderer.render_terrain_pass_render_fn = terrain_render_pass.renderFn;
    ctx.renderer.render_terrain_pass_render_shadow_map_fn = terrain_render_pass.renderShadowMapFn;
    ctx.renderer.render_terrain_pass_create_descriptor_sets_fn = terrain_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_terrain_pass_prepare_descriptor_sets_fn = terrain_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_terrain_pass_unload_descriptor_sets_fn = terrain_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_terrain_pass_user_data = terrain_pass;

    const deferred_shading_pass = DeferredShadingRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_deferred_shading_pass_render_fn = deferred_shading_render_pass.renderFn;
    ctx.renderer.render_deferred_shading_pass_imgui_fn = deferred_shading_render_pass.renderImGuiFn;
    ctx.renderer.render_deferred_shading_pass_create_descriptor_sets_fn = deferred_shading_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_deferred_shading_pass_prepare_descriptor_sets_fn = deferred_shading_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_deferred_shading_pass_unload_descriptor_sets_fn = deferred_shading_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_deferred_shading_pass_user_data = deferred_shading_pass;

    const skybox_pass = SkyboxRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_skybox_pass_render_fn = skybox_render_pass.renderFn;
    ctx.renderer.render_skybox_pass_create_descriptor_sets_fn = skybox_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_skybox_pass_prepare_descriptor_sets_fn = skybox_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_skybox_pass_unload_descriptor_sets_fn = skybox_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_skybox_pass_user_data = skybox_pass;

    const tonemap_pass = TonemapRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_tonemap_pass_render_fn = tonemap_render_pass.renderFn;
    ctx.renderer.render_tonemap_pass_create_descriptor_sets_fn = tonemap_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_tonemap_pass_prepare_descriptor_sets_fn = tonemap_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_tonemap_pass_unload_descriptor_sets_fn = tonemap_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_tonemap_pass_user_data = tonemap_pass;

    const ui_pass = UIRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_ui_pass_render_fn = ui_render_pass.renderFn;
    ctx.renderer.render_ui_pass_create_descriptor_sets_fn = ui_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_ui_pass_prepare_descriptor_sets_fn = ui_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_ui_pass_unload_descriptor_sets_fn = ui_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_ui_pass_user_data = ui_pass;

    const im3d_pass = Im3dRenderPass.create(ctx.renderer, ctx.ecsu_world, ctx.allocator);
    ctx.renderer.render_im3d_pass_render_fn = im3d_render_pass.renderFn;
    ctx.renderer.render_im3d_pass_create_descriptor_sets_fn = im3d_render_pass.createDescriptorSetsFn;
    ctx.renderer.render_im3d_pass_prepare_descriptor_sets_fn = im3d_render_pass.prepareDescriptorSetsFn;
    ctx.renderer.render_im3d_pass_unload_descriptor_sets_fn = im3d_render_pass.unloadDescriptorSetsFn;
    ctx.renderer.render_im3d_pass_user_data = im3d_pass;

    system.* = .{
        .allocator = ctx.allocator,
        .ecsu_world = ctx.ecsu_world,
        .input_frame_data = ctx.input_frame_data,
        .renderer = ctx.renderer,
        .terrain_render_pass = terrain_pass,
        .geometry_render_pass = geometry_pass,
        .deferred_shading_render_pass = deferred_shading_pass,
        .skybox_render_pass = skybox_pass,
        .tonemap_render_pass = tonemap_pass,
        .ui_render_pass = ui_pass,
        .im3d_render_pass = im3d_pass,
        .render_imgui = false,
        .pre_sys = pre_sys,
        .post_sys = post_sys,
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

    system.im3d_render_pass.destroy();
    system.renderer.render_im3d_pass_render_fn = null;
    system.renderer.render_im3d_pass_prepare_descriptor_sets_fn = null;
    system.renderer.render_im3d_pass_unload_descriptor_sets_fn = null;
    system.renderer.render_im3d_pass_user_data = null;

    system.allocator.destroy(system);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn preUpdate(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Renderer System: Pre Update", 0x00_ff_ff_00);
    defer trazy_zone.End();

    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));

    if (system.input_frame_data.just_pressed(config.input.toggle_imgui)) {
        system.render_imgui = !system.render_imgui;
        system.renderer.render_imgui = system.render_imgui;
    }

    var rctx = system.renderer;
    const environment_info = system.ecsu_world.getSingleton(fd.EnvironmentInfo).?;
    rctx.time = environment_info.world_time;

    if (rctx.window.frame_buffer_size[0] != rctx.window_width or rctx.window.frame_buffer_size[1] != rctx.window_height) {
        rctx.window_width = rctx.window.frame_buffer_size[0];
        rctx.window_height = rctx.window.frame_buffer_size[1];

        const reload_desc = graphics.ReloadDesc{ .mType = .{ .RESIZE = true } };
        rctx.requestReload(reload_desc);
    }

    zgui.backend.newFrame(@intCast(rctx.window_width), @intCast(rctx.window_height));

    var camera_entity = util.getActiveCameraEnt(system.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
        forward: *const fd.Forward,
    });
    const camera_position = camera_comps.transform.getPos00();
    const camera_forward = camera_comps.forward;

    var im3d_app_data = im3d.Im3d.GetAppData();
    im3d_app_data.m_deltaTime = iter.iter.delta_time;
    im3d_app_data.m_viewportSize = .{ .x = @floatFromInt(rctx.window_width), .y = @floatFromInt(rctx.window_height) };
    im3d_app_data.m_viewOrigin = .{ .x = camera_position[0], .y = camera_position[1], .z = camera_position[2] };
    im3d_app_data.m_viewDirection = .{ .x = camera_forward.x, .y = camera_forward.y, .z = camera_forward.z };
    im3d_app_data.m_worldUp = .{ .x = 0, .y = 1, .z = 0 };
    im3d_app_data.m_projOrtho = false;
    im3d_app_data.m_projScaleY = std.math.tan(camera_comps.camera.fov * 0.5) * 2.0;
    // const lol = std.mem.zeroes(im3d.Im3d.Mat4);
    // im3d_app_data.setCullFrustum(&lol, true);

    im3d.Im3d.NewFrame();
}

fn postUpdate(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Renderer System: Post Update", 0x00_ff_ff_00);
    defer trazy_zone.End();

    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    var rctx = system.renderer;

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
