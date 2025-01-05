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

const TerrainRenderPass = @import("renderer_system/terrain_render_pass.zig").TerrainRenderPass;
const GeometryRenderPass = @import("renderer_system/geometry_render_pass.zig").GeometryRenderPass;
const DeferredShadingRenderPass = @import("renderer_system/deferred_shading_render_pass.zig").DeferredShadingRenderPass;
const AtmosphereRenderPass = @import("renderer_system/atmosphere_render_pass.zig").AtmosphereRenderPass;
const WaterRenderPass = @import("renderer_system/water_render_pass.zig").WaterRenderPass;
const PostProcessingRenderPass = @import("renderer_system/post_processing_render_pass.zig").PostProcessingRenderPass;
const UIRenderPass = @import("renderer_system/ui_render_pass.zig").UIRenderPass;
const Im3dRenderPass = @import("renderer_system/im3d_render_pass.zig").Im3dRenderPass;

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    prefab_mgr: *PrefabManager,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

pub const SystemUpdateContext = struct {
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    state: struct {
        terrain_render_pass: *TerrainRenderPass,
        geometry_render_pass: *GeometryRenderPass,
        deferred_shading_render_pass: *DeferredShadingRenderPass,
        atmosphere_render_pass: *AtmosphereRenderPass,
        water_render_pass: *WaterRenderPass,
        ui_render_pass: *UIRenderPass,
        im3d_render_pass: *Im3dRenderPass,
        render_imgui: bool,
    },
};

pub fn create(name: IdLocal, create_ctx: SystemCreateCtx) void {
    _ = name;
    const arena_system_lifetime = create_ctx.arena_system_lifetime;
    const pass_allocator = create_ctx.heap_allocator;
    const ctx_renderer = create_ctx.renderer;
    const ecsu_world = create_ctx.ecsu_world;

    const geometry_pass = arena_system_lifetime.create(GeometryRenderPass) catch unreachable;
    geometry_pass.init(ctx_renderer, ecsu_world, create_ctx.prefab_mgr, pass_allocator);

    const terrain_pass = arena_system_lifetime.create(TerrainRenderPass) catch unreachable;
    terrain_pass.init(ctx_renderer, ecsu_world, create_ctx.world_patch_mgr, pass_allocator);

    const deferred_shading_pass = arena_system_lifetime.create(DeferredShadingRenderPass) catch unreachable;
    deferred_shading_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const atmosphere_pass = arena_system_lifetime.create(AtmosphereRenderPass) catch unreachable;
    atmosphere_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const water_pass = arena_system_lifetime.create(WaterRenderPass) catch unreachable;
    water_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const post_processing_pass = arena_system_lifetime.create(PostProcessingRenderPass) catch unreachable;
    post_processing_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const ui_pass = arena_system_lifetime.create(UIRenderPass) catch unreachable;
    ui_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const im3d_pass = arena_system_lifetime.create(Im3dRenderPass) catch unreachable;
    im3d_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .terrain_render_pass = terrain_pass,
        .geometry_render_pass = geometry_pass,
        .deferred_shading_render_pass = deferred_shading_pass,
        .atmosphere_render_pass = atmosphere_pass,
        .water_render_pass = water_pass,
        .ui_render_pass = ui_pass,
        .im3d_render_pass = im3d_pass,
        .render_imgui = false,
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = preUpdate;
        system_desc.ctx = update_ctx;
        return ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "Render System PreUpdate",
            ecs.PreUpdate,
            &system_desc,
        );
    }

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = postUpdate;
        system_desc.ctx = update_ctx;
        return ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "Render System PostUpdate",
            ecs.PostUpdate,
            &system_desc,
        );
    }
}

pub fn destroy(system: *SystemUpdateContext) void {
    system.terrain_render_pass.destroy();
    system.geometry_render_pass.destroy();
    system.deferred_shading_render_pass.destroy();
    system.atmosphere_render_pass.destroy();
    system.water_render_pass.destroy();
    system.ui_render_pass.destroy();
    system.im3d_render_pass.destroy();

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
    const system: *SystemUpdateContext = @ptrCast(@alignCast(iter.iter.ctx));

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
    const system: *SystemUpdateContext = @ptrCast(@alignCast(iter.iter.ctx));
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
