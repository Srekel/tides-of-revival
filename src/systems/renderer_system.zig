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

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemCreateCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    arena_system_lifetime: std.mem.Allocator,
    arena_system_update: std.mem.Allocator,
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    prefab_mgr: *PrefabManager,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
};

pub const SystemUpdateContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    heap_allocator: std.mem.Allocator,
    arena_system_update: std.mem.Allocator,
    ecsu_world: ecsu.World,
    input_frame_data: *input.FrameData,
    renderer: *renderer.Renderer,
    state: struct {
        render_imgui: bool,

        query_point_lights: *ecs.query_t,
        point_lights: std.ArrayList(renderer_types.PointLight),

        query_ocean_tiles: *ecs.query_t,
        ocean_tiles: std.ArrayList(renderer_types.OceanTile),

        query_static_entities: *ecs.query_t,
        // static_entities: std.ArrayList(renderer_types.RenderableEntity),

        query_dynamic_entities: *ecs.query_t,
        dynamic_entities: std.ArrayList(renderer_types.DynamicEntity),

        query_ui_images: *ecs.query_t,
        ui_images: std.ArrayList(renderer_types.UiImage),

        query_scripts: *ecs.query_t,

        added_static_entities: std.ArrayList(renderer_types.RenderableEntity) = undefined,
        removed_static_entities: std.ArrayList(renderer_types.RenderableEntityId) = undefined,

        monitor_ent: ecs.entity_t = undefined,
    },
};

pub fn create(create_ctx: SystemCreateCtx) void {
    const pass_allocator = create_ctx.arena_system_lifetime;
    const ecsu_world = create_ctx.ecsu_world;

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

    const query_static_entities = ecs.query_init(ecsu_world.world, &.{
        .entity = ecs.new_entity(ecsu_world.world, "query_static_entities"),
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.Renderable), .inout = .In },
            .{ .id = ecs.id(fd.Transform), .inout = .In },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
    }) catch unreachable;

    const query_dynamic_entities = ecs.query_init(ecsu_world.world, &.{
        .entity = ecs.new_entity(ecsu_world.world, "query_dynamic_entities"),
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.LodGroup), .inout = .In },
            .{ .id = ecs.id(fd.Transform), .inout = .In },
            .{ .id = ecs.id(fd.Scale), .inout = .In },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 3),
    }) catch unreachable;

    const query_ui_images = ecs.query_init(ecsu_world.world, &.{
        .entity = ecs.new_entity(ecsu_world.world, "query_ui_images"),
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.UIImage), .inout = .In },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 1),
    }) catch unreachable;

    const query_scripts = ecs.query_init(ecsu_world.world, &.{
        .entity = ecs.new_entity(ecsu_world.world, "query_scripts"),
        .terms = [_]ecs.term_t{
            .{ .id = ecs.id(fd.MadeByAScript), .inout = .InOut },
        } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 1),
    }) catch unreachable;

    const update_ctx = create_ctx.arena_system_lifetime.create(SystemUpdateContext) catch unreachable;
    update_ctx.* = SystemUpdateContext.view(create_ctx);
    update_ctx.*.state = .{
        .render_imgui = false,
        .query_point_lights = query_point_lights,
        .query_scripts = query_scripts,
        .point_lights = std.ArrayList(renderer_types.PointLight).init(pass_allocator),
        .query_ocean_tiles = query_ocean_tiles,
        .ocean_tiles = std.ArrayList(renderer_types.OceanTile).init(pass_allocator),
        .query_static_entities = query_static_entities,
        // .static_entities = std.ArrayList(renderer_types.RenderableEntity).init(pass_allocator),
        .query_dynamic_entities = query_dynamic_entities,
        .dynamic_entities = std.ArrayList(renderer_types.DynamicEntity).init(pass_allocator),
        .query_ui_images = query_ui_images,
        .ui_images = std.ArrayList(renderer_types.UiImage).init(pass_allocator),
        .added_static_entities = std.ArrayList(renderer_types.RenderableEntity).init(pass_allocator),
        .removed_static_entities = std.ArrayList(renderer_types.RenderableEntityId).init(pass_allocator),
    };

    const observer_desc: ecs.observer_desc_t = .{
        .query = .{
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(fd.Renderable), .inout = .In },
                .{ .id = ecs.id(fd.Transform), .inout = .In },
                // .{ .id = ecs.id(fd.LolTest), .inout = .In },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 2),
        },
        .events = [_]ecs.entity_t{ ecs.OnSet, ecs.OnRemove, 0, 0, 0, 0, 0, 0 },
        .callback = onMonitorRenderable,
        .ctx = update_ctx,
    };
    update_ctx.*.state.monitor_ent = ecs.observer_init(ecsu_world.world, &observer_desc);

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

    system.ecsu_world.delete(system.state.monitor_ent);

    system.state.point_lights.deinit();
    system.state.ocean_tiles.deinit();
    // system.state.static_entities.deinit();
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

    // Find sun light
    {
        const sun_entity = util.getSun(system.ecsu_world);
        const sun_comps = sun_entity.?.getComps(struct {
            light: *const fd.DirectionalLight,
            rotation: *const fd.Rotation,
        });
        const z_quat = sun_comps.rotation.asZM();
        const z_mat = zm.matFromQuat(z_quat);
        const z_forward = zm.normalize3(zm.rotate(z_quat, zm.Vec{ 0, 0, -1, 0 }));
        update_desc.sun_light = renderer_types.DirectionalLight{
            .direction = [3]f32{ z_forward[0], z_forward[1], z_forward[2] },
            .color = [3]f32{ sun_comps.light.color.r, sun_comps.light.color.g, sun_comps.light.color.b },
            .intensity = sun_comps.light.intensity,
            .world_inv = undefined,
            .cast_shadows = sun_comps.light.cast_shadows,
            .shadow_intensity = sun_comps.light.shadow_intensity,
        };
        zm.storeMat(&update_desc.sun_light.world_inv, zm.inverse(z_mat));
    }

    // Find moon light
    {
        const moon_entity = util.getMoon(system.ecsu_world);
        const moon_comps = moon_entity.?.getComps(struct {
            light: *const fd.DirectionalLight,
            rotation: *const fd.Rotation,
        });
        const z_quat = moon_comps.rotation.asZM();
        const z_mat = zm.matFromQuat(z_quat);
        const z_forward = zm.rotate(z_quat, zm.Vec{ 0, 0, -1, 0 });
        update_desc.moon_light = renderer_types.DirectionalLight{
            .direction = [3]f32{ z_forward[0], z_forward[1], z_forward[2] },
            .color = [3]f32{ moon_comps.light.color.r, moon_comps.light.color.g, moon_comps.light.color.b },
            .intensity = moon_comps.light.intensity,
            .world_inv = undefined,
            .cast_shadows = moon_comps.light.cast_shadows,
            .shadow_intensity = moon_comps.light.shadow_intensity,
        };
        zm.storeMat(&update_desc.moon_light.world_inv, zm.inverse(z_mat));
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

    var query_scripts_iter = ecs.query_iter(system.ecsu_world.world, system.state.query_scripts);
    while (ecs.query_next(&query_scripts_iter)) {
        // std.log.info("lol {}", .{it.count()});
        for (query_scripts_iter.entities()) |ent| {
            const ent2 = ecsu.Entity.init(system.ecsu_world.world, ent);
            ent2.remove(fd.MadeByAScript); // only run once per script entity

            const scale = ent2.get(fd.Scale).?;
            const rot = ent2.get(fd.Rotation).?;
            const pos = ent2.get(fd.Position).?;
            const z_scale_matrix = zm.scaling(scale.x, scale.y, scale.z);
            const z_rot_matrix = zm.matFromQuat(rot.asZM());
            const z_translate_matrix = zm.translation(pos.x, pos.y, pos.z);
            const z_sr_matrix = zm.mul(z_scale_matrix, z_rot_matrix);
            const z_srt_matrix = zm.mul(z_sr_matrix, z_translate_matrix);

            const z_world_matrix = z_srt_matrix;

            var transform: fd.Transform = undefined;
            zm.storeMat43(&transform.matrix, z_world_matrix);

            ent2.set(transform);
        }
    }

    // Find all static entity changes
    update_desc.added_static_entities = std.ArrayList(renderer_types.RenderableEntity).initCapacity(system.arena_system_update, system.state.added_static_entities.items.len) catch unreachable;
    update_desc.removed_static_entities = std.ArrayList(renderer_types.RenderableEntityId).initCapacity(system.arena_system_update, system.state.removed_static_entities.items.len) catch unreachable;
    update_desc.added_static_entities.appendSliceAssumeCapacity(system.state.added_static_entities.items);
    update_desc.removed_static_entities.appendSliceAssumeCapacity(system.state.removed_static_entities.items);
    system.state.added_static_entities.clearRetainingCapacity();
    system.state.removed_static_entities.clearRetainingCapacity();

    // Find all dynamic entities
    {
        system.state.dynamic_entities.clearRetainingCapacity();

        var iter = ecs.query_iter(system.ecsu_world.world, system.state.query_dynamic_entities);
        while (ecs.query_next(&iter)) {
            const lod_groups = ecs.field(&iter, fd.LodGroup, 0).?;
            const transforms = ecs.field(&iter, fd.Transform, 1).?;
            const scales = ecs.field(&iter, fd.Scale, 2).?;

            for (lod_groups, transforms, scales) |*lod_group_component, transform, scale| {
                var world: [16]f32 = undefined;
                storeMat44(transform.matrix[0..], world[0..]);

                var dynamic_entity = renderer_types.DynamicEntity{
                    .world = zm.loadMat(world[0..]),
                    .position = transform.getPos00(),
                    .lod_count = lod_group_component.lod_count,
                    .scale = @max(scale.x, @max(scale.y, scale.z)),
                };
                @memcpy(&dynamic_entity.lods, &lod_group_component.lods);

                system.state.dynamic_entities.append(dynamic_entity) catch unreachable;
            }
        }

        update_desc.dynamic_entities = &system.state.dynamic_entities;
    }

    // Find all UI Images
    {
        system.state.ui_images.clearRetainingCapacity();

        const screen_height: f32 = @floatFromInt(system.renderer.window_height);

        var iter = ecs.query_iter(system.ecsu_world.world, system.state.query_ui_images);
        while (ecs.query_next(&iter)) {
            const ui_images = ecs.field(&iter, fd.UIImage, 0).?;
            for (ui_images) |ui_image| {
                system.state.ui_images.append(.{
                    .rect = [4]f32{
                        screen_height - (ui_image.rect.y + ui_image.rect.height),
                        ui_image.rect.x + ui_image.rect.width,
                        screen_height - ui_image.rect.y,
                        ui_image.rect.x,
                    },
                    .color = [4]f32{ ui_image.material.color[0], ui_image.material.color[1], ui_image.material.color[2], ui_image.material.color[3] },
                    .texture_index = system.renderer.getTextureBindlessIndex(ui_image.material.texture),
                    .render_order = ui_image.render_order,
                    ._padding0 = [2]u32{ 42, 42 },
                }) catch unreachable;
            }
        }

        update_desc.ui_images = &system.state.ui_images;
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

//  ██████╗ ██████╗ ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
// ██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
// ██║   ██║██████╔╝███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
// ██║   ██║██╔══██╗╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
// ╚██████╔╝██████╔╝███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
//  ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝

// Observer callback
fn onMonitorRenderable(it: *ecs.iter_t) callconv(.C) void {
    const ctx: *SystemUpdateContext = @alignCast(@ptrCast(it.ctx.?));

    const renderables = ecs.field(it, fd.Renderable, 0).?;
    const transforms = ecs.field(it, fd.Transform, 1).?;
    if (it.event == ecs.OnSet) {
        for (renderables, transforms, it.entities()) |renderable, transform, entity| {
            var world: [16]f32 = undefined;
            storeMat44(transform.matrix[0..], world[0..]);

            const renderable_entity: renderer_types.RenderableEntity = .{
                .entity_id = entity,
                .renderable_id = renderable.id,
                .world = zm.loadMat(&world),
                .draw_bounds = renderable.draw_bounds,
            };
            ctx.state.added_static_entities.append(renderable_entity) catch unreachable;
        }
    } else if (it.event == ecs.OnRemove) {
        for (it.entities()) |entity| {
            ctx.state.removed_static_entities.append(entity) catch unreachable;
        }
    }
}
