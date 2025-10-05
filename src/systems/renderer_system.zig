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
const PSOManager = @import("../renderer/pso.zig").PSOManager;
const renderer = @import("../renderer/renderer.zig");
const renderer_types = @import("../renderer/types.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../util.zig");
const zm = @import("zmath");
const zgui = @import("zgui");
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");

const TerrainRenderPass = @import("renderer_system/terrain_render_pass.zig").TerrainRenderPass;
const GeometryRenderPass = @import("renderer_system/geometry_render_pass.zig").GeometryRenderPass;
const GpuDrivenRenderPass = @import("renderer_system/gpu_driven_render_pass.zig").GpuDrivenRenderPass;
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
    pso_mgr: *PSOManager,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

pub const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    state: struct {
        terrain_render_pass: *TerrainRenderPass,
        geometry_render_pass: *GeometryRenderPass,
        gpu_driven_render_pass: *GpuDrivenRenderPass,
        ui_render_pass: *UIRenderPass,
        im3d_render_pass: *Im3dRenderPass,
        render_imgui: bool,

        query_point_lights: *ecs.query_t,
        point_lights: std.ArrayList(renderer_types.PointLight),

        query_ocean_tiles: *ecs.query_t,
        ocean_tiles: std.ArrayList(renderer_types.OceanTile),
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const arena_system_lifetime = create_ctx.arena_system_lifetime;
    const pass_allocator = create_ctx.heap_allocator;
    const ctx_renderer = create_ctx.renderer;
    const ecsu_world = create_ctx.ecsu_world;
    const prefab_mgr = create_ctx.prefab_mgr;
    const pso_mgr = create_ctx.pso_mgr;

    const geometry_render_pass = arena_system_lifetime.create(GeometryRenderPass) catch unreachable;
    geometry_render_pass.init(ctx_renderer, ecsu_world, create_ctx.prefab_mgr, pass_allocator);

    const terrain_render_pass = arena_system_lifetime.create(TerrainRenderPass) catch unreachable;
    terrain_render_pass.init(ctx_renderer, ecsu_world, create_ctx.world_patch_mgr, pass_allocator);

    const gpu_driven_render_pass = arena_system_lifetime.create(GpuDrivenRenderPass) catch unreachable;
    gpu_driven_render_pass.init(ctx_renderer, ecsu_world, prefab_mgr, pso_mgr, pass_allocator);

    const ui_render_pass = arena_system_lifetime.create(UIRenderPass) catch unreachable;
    ui_render_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const im3d_render_pass = arena_system_lifetime.create(Im3dRenderPass) catch unreachable;
    im3d_render_pass.init(ctx_renderer, ecsu_world, pass_allocator);

    const query_point_lights = ecs.query_init(ecsu_world.world, &.{
        .entity = ecs.new_entity(ecsu_world.world, "query_point_lights"),
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Transform), .inout = .Out },
            .{ .id = ecs.id(fd.PointLight), .inout = .Out },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
    }) catch unreachable;

    const query_ocean_tiles = ecs.query_init(ecsu_world.world, &.{
            .entity = ecs.new_entity(ecsu_world.world, "query_ocean_tiles"),
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(fd.Transform), .inout = .In },
                .{ .id = ecs.id(fd.Water), .inout = .In },
                .{ .id = ecs.id(fd.Scale), .inout = .In },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 3),
        }) catch unreachable;

    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .terrain_render_pass = terrain_render_pass,
        .geometry_render_pass = geometry_render_pass,
        .gpu_driven_render_pass = gpu_driven_render_pass,
        .ui_render_pass = ui_render_pass,
        .im3d_render_pass = im3d_render_pass,
        .render_imgui = false,
        .query_point_lights = query_point_lights,
        .point_lights = std.ArrayList(renderer_types.PointLight).init(pass_allocator),
        .query_ocean_tiles = query_ocean_tiles,
        .ocean_tiles = std.ArrayList(renderer_types.OceanTile).init(pass_allocator),
    };

    {
        var system_desc = ecs.system_desc_t{};
        system_desc.callback = preUpdate;
        system_desc.ctx = update_ctx;
        system_desc.ctx_free = destroy;
        _ = ecs.SYSTEM(
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
        _ = ecs.SYSTEM(
            create_ctx.ecsu_world.world,
            "Render System PostUpdate",
            ecs.PostUpdate,
            &system_desc,
        );
    }
}

pub fn destroy(ctx: ?*anyopaque) callconv(.C) void {
    const system: *SystemUpdateContext = @ptrCast(@alignCast(ctx));
    system.state.terrain_render_pass.destroy();
    system.state.geometry_render_pass.destroy();
    system.state.gpu_driven_render_pass.destroy();
    system.state.ui_render_pass.destroy();
    system.state.im3d_render_pass.destroy();

    system.state.point_lights.deinit();
    system.state.ocean_tiles.deinit();
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn preUpdate(it: *ecs.iter_t) callconv(.C) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Renderer System: Pre Update", 0x00_ff_ff_00);
    defer trazy_zone.End();

    // defer ecs.iter_fini(it);
    const system: *SystemUpdateContext = @ptrCast(@alignCast(it.ctx));

    if (system.input_frame_data.just_pressed(config.input.toggle_imgui)) {
        system.state.render_imgui = !system.state.render_imgui;
        system.renderer.render_imgui = system.state.render_imgui;
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
    im3d_app_data.m_deltaTime = it.delta_time;
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

fn postUpdate(it: *ecs.iter_t) callconv(.C) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Renderer System: Post Update", 0x00_ff_ff_00);
    defer trazy_zone.End();

    // defer ecs.iter_fini(it);
    const system: *SystemUpdateContext = @ptrCast(@alignCast(it.ctx));

    // Collect scene data
    var update_desc = renderer_types.UpdateDesc{};

    update_desc.time_of_day_01 = util.getTimeOfDayPercent(system.ecsu_world);

    // Find sun light
    {
        const sun_entity = util.getSun(system.ecsu_world);
        const sun_comps = sun_entity.?.getComps(struct {
            light: *const fd.DirectionalLight,
            rotation: *const fd.Rotation,
        });
        const z_forward = zm.rotate(sun_comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 });
        update_desc.sun_light = renderer_types.DirectionalLight{
            .direction = [3]f32{ -z_forward[0], -z_forward[1], -z_forward[2] },
            .shadow_map = 0,
            .color = [3]f32{ sun_comps.light.color.r, sun_comps.light.color.g, sun_comps.light.color.b },
            .intensity = sun_comps.light.intensity,
            .shadow_range = sun_comps.light.shadow_range,
            ._pad = [2]f32{ 42, 42 },
            .shadow_map_dimensions = 0,
            .view_proj = [16]f32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        };
    }

    // Find all point lights
    {
        system.state.point_lights.clearRetainingCapacity();
        var query_point_lights_iter = ecs.query_iter(system.ecsu_world.world, system.state.query_point_lights);
        while (ecs.query_next(&query_point_lights_iter)) {
            const transforms = ecs.field(&query_point_lights_iter, fd.Transform, 0).?;
            const lights = ecs.field(&query_point_lights_iter, fd.PointLight, 1).?;
            for (transforms, lights) |transform, light| {
                const point_light = renderer_types.PointLight{
                    .position = transform.getPos00(),
                    .radius = light.range,
                    .color = [3]f32{ light.color.r, light.color.g, light.color.b },
                    .intensity = light.intensity,
                };

                system.state.point_lights.append(point_light) catch unreachable;
            }
        }
        update_desc.point_lights = &system.state.point_lights;
    }

    // Find all ocean tiles
    {
        system.state.ocean_tiles.clearRetainingCapacity();

        var iter = ecs.query_iter(system.ecsu_world.world, system.state.query_ocean_tiles);
        while (ecs.query_next(&iter)) {
            const transforms = ecs.field(&iter, fd.Transform, 0).?;
            const waters = ecs.field(&iter, fd.Water, 1).?;
            const scales = ecs.field(&iter, fd.Scale, 2).?;
            for (transforms, waters, scales) |transform, _, scale| {
                var world: [16]f32 = undefined;
                storeMat44(transform.matrix[0..], &world);

                var ocean_tile = renderer_types.OceanTile{};
                ocean_tile.world = zm.loadMat(world[0..]);
                ocean_tile.scale = @max(scale.x, @max(scale.y, scale.z));

                system.state.ocean_tiles.append(ocean_tile) catch unreachable;
            }
        }

        update_desc.ocean_tiles = &system.state.ocean_tiles;
    }

    // Find Height Fog
    {
        update_desc.height_fog = renderer_types.HeightFogSettings{};
        const height_fog_entity = util.getHeightFog(system.ecsu_world);
        if (height_fog_entity) |entity| {
            const comps = entity.getComps(struct { height_fog: *const fd.HeightFog });
            update_desc.height_fog.color[0] = comps.height_fog.color.r;
            update_desc.height_fog.color[1] = comps.height_fog.color.g;
            update_desc.height_fog.color[2] = comps.height_fog.color.b;
            update_desc.height_fog.density = comps.height_fog.density;
        }
    }

    system.renderer.update(update_desc);

    system.renderer.draw();
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

inline fn storeMat44(mat43: *const [12]f32, mat44: *[16]f32) void {
    mat44[0] = mat43[0];
    mat44[1] = mat43[1];
    mat44[2] = mat43[2];
    mat44[3] = 0;
    mat44[4] = mat43[3];
    mat44[5] = mat43[4];
    mat44[6] = mat43[5];
    mat44[7] = 0;
    mat44[8] = mat43[6];
    mat44[9] = mat43[7];
    mat44[10] = mat43[8];
    mat44[11] = 0;
    mat44[12] = mat43[9];
    mat44[13] = mat43[10];
    mat44[14] = mat43[11];
    mat44[15] = 1;
}