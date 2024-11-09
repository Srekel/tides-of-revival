const std = @import("std");

const config = @import("../../config/config.zig");
const context = @import("../../core/context.zig");
const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const tides_math = @import("../../core/math.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const world_patch_manager = @import("../../worldpatch/world_patch_manager.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const lod_load_range = 300;
const max_instances = 16384;
const invalid_index = std.math.maxInt(u32);
const lod_3_patches_side = config.world_size_x / config.largest_patch_width;
const lod_3_patches_total = lod_3_patches_side * lod_3_patches_side;

const TerrainRenderSettings = struct {
    triplanar_mapping: bool,
    black_point: f32,
    white_point: f32,
};

const TerrainLayer = struct {
    diffuse: renderer.TextureHandle,
    normal: renderer.TextureHandle,
    arm: renderer.TextureHandle,
    height: renderer.TextureHandle,
};

const TerrainLayerMaterial = extern struct {
    diffuse_index: u32,
    normal_index: u32,
    arm_index: u32,
    height_index: u32,
};

const InstanceData = struct {
    object_to_world: [16]f32,
    heightmap_index: u32,
    lod: u32,
    padding1: [2]u32,
};

pub const UniformFrameData = struct {
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
    triplanar_mapping: f32,
    black_point: f32,
    white_point: f32,
    _padding: [1]f32,
};

pub const ShadowsUniformFrameData = struct {
    projection_view: [16]f32,
};

const PushConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
    instance_material_buffer_index: u32,
};

pub const TerrainRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    terrain_render_settings: TerrainRenderSettings,

    shadows_uniform_frame_data: ShadowsUniformFrameData,
    shadows_uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    shadows_descriptor_set: [*c]graphics.DescriptorSet,
    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_set: [*c]graphics.DescriptorSet,

    frame_instance_count: u32,
    terrain_layers_buffer: renderer.BufferHandle,
    instance_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    instance_data: *[max_instances]InstanceData,

    terrain_quad_tree_nodes: std.ArrayList(QuadTreeNode),
    terrain_lod_meshes: std.ArrayList(renderer.MeshHandle),
    quads_to_render: std.ArrayList(u32),
    quads_to_load: std.ArrayList(u32),

    heightmap_patch_type_id: world_patch_manager.PatchTypeId,

    cam_pos_old: [3]f32 = .{ -100000, 0, -100000 }, // NOTE(Anders): Assumes only one camera

    pub fn init(self: *TerrainRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, world_patch_mgr: *world_patch_manager.WorldPatchManager, allocator: std.mem.Allocator) void {
        const terrain_render_settings = TerrainRenderSettings{
            .triplanar_mapping = true,
            .black_point = 0,
            .white_point = 1.0,
        };

        // TODO(gmodarelli): This is just enough for a single sector, but it's good for testing
        const max_quad_tree_nodes: usize = 85 * lod_3_patches_total;
        var terrain_quad_tree_nodes = std.ArrayList(QuadTreeNode).initCapacity(allocator, max_quad_tree_nodes) catch unreachable;
        const quads_to_render = std.ArrayList(u32).init(allocator);
        const quads_to_load = std.ArrayList(u32).init(allocator);

        // Create initial sectors
        {
            const patch_half_size = @as(f32, @floatFromInt(config.largest_patch_width)) / 2.0;
            var patch_y: u32 = 0;
            while (patch_y < lod_3_patches_side) : (patch_y += 1) {
                var patch_x: u32 = 0;
                while (patch_x < lod_3_patches_side) : (patch_x += 1) {
                    terrain_quad_tree_nodes.appendAssumeCapacity(.{
                        .center = [2]f32{
                            @as(f32, @floatFromInt(patch_x * config.largest_patch_width)) + patch_half_size,
                            @as(f32, @floatFromInt(patch_y * config.largest_patch_width)) + patch_half_size,
                        },
                        .size = [2]f32{ patch_half_size, patch_half_size },
                        .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
                        .mesh_lod = 3,
                        .patch_index = [2]u32{ patch_x, patch_y },
                        .heightmap_handle = null,
                    });
                }
            }

            std.debug.assert(terrain_quad_tree_nodes.items.len == lod_3_patches_total);

            var sector_index: u32 = 0;
            while (sector_index < lod_3_patches_total) : (sector_index += 1) {
                const node = &terrain_quad_tree_nodes.items[sector_index];
                divideQuadTreeNode(&terrain_quad_tree_nodes, node);
            }
        }

        var arena_state = std.heap.ArenaAllocator.init(allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        var meshes = std.ArrayList(renderer.MeshHandle).init(allocator);

        loadMesh(rctx, "prefabs/environment/terrain/terrain_patch_0.bin", &meshes) catch unreachable;
        loadMesh(rctx, "prefabs/environment/terrain/terrain_patch_1.bin", &meshes) catch unreachable;
        loadMesh(rctx, "prefabs/environment/terrain/terrain_patch_2.bin", &meshes) catch unreachable;
        loadMesh(rctx, "prefabs/environment/terrain/terrain_patch_3.bin", &meshes) catch unreachable;

        const heightmap_patch_type_id = world_patch_mgr.getPatchTypeId(config.patch_type_heightmap);

        var terrain_layers = std.ArrayList(TerrainLayer).init(arena);
        loadResources(
            allocator,
            rctx,
            &terrain_quad_tree_nodes,
            &terrain_layers,
            world_patch_mgr,
            heightmap_patch_type_id,
        ) catch unreachable;

        var terrain_layer_texture_indices = std.ArrayList(TerrainLayerMaterial).initCapacity(arena, terrain_layers.items.len) catch unreachable;
        var terrain_layer_index: u32 = 0;
        while (terrain_layer_index < terrain_layers.items.len) : (terrain_layer_index += 1) {
            const terrain_layer = &terrain_layers.items[terrain_layer_index];
            terrain_layer_texture_indices.appendAssumeCapacity(.{
                .diffuse_index = rctx.getTextureBindlessIndex(terrain_layer.diffuse),
                .normal_index = rctx.getTextureBindlessIndex(terrain_layer.normal),
                .arm_index = rctx.getTextureBindlessIndex(terrain_layer.arm),
                .height_index = rctx.getTextureBindlessIndex(terrain_layer.height),
            });
        }

        const transform_layer_data = renderer.Slice{
            .data = @ptrCast(terrain_layer_texture_indices.items),
            .size = terrain_layer_texture_indices.items.len * @sizeOf(TerrainLayerMaterial),
        };
        const terrain_layers_buffer = rctx.createBindlessBuffer(transform_layer_data, "Terrain Layers Buffer");

        // Create instance buffers.
        const instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Terrain Quad Tree Instance Data Buffer");
            }

            break :blk buffers;
        };

        const shadows_uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ShadowsUniformFrameData);
            }

            break :blk buffers;
        };

        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .world_patch_mgr = world_patch_mgr,
            .terrain_render_settings = terrain_render_settings,
            .shadows_uniform_frame_data = std.mem.zeroes(ShadowsUniformFrameData),
            .shadows_uniform_frame_buffers = shadows_uniform_frame_buffers,
            .shadows_descriptor_set = undefined,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .descriptor_set = undefined,
            .instance_data_buffers = instance_data_buffers,
            .instance_data = allocator.create([max_instances]InstanceData) catch unreachable,
            .frame_instance_count = 0,
            .terrain_layers_buffer = terrain_layers_buffer,
            .terrain_lod_meshes = meshes,
            .terrain_quad_tree_nodes = terrain_quad_tree_nodes,
            .quads_to_render = quads_to_render,
            .quads_to_load = quads_to_load,
            .heightmap_patch_type_id = heightmap_patch_type_id,
            .cam_pos_old = .{ -100000, 0, -100000 }, // NOTE(Anders): Assumes only one camera
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_gbuffer_pass_fn =  renderGBuffer,
            .render_shadow_pass_fn = renderShadowMap,
            .render_imgui_fn = renderImGui,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *TerrainRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);

        unloadDescriptorSets(@ptrCast(self));

        self.terrain_lod_meshes.deinit();
        self.terrain_quad_tree_nodes.deinit();
        self.quads_to_render.deinit();
        self.quads_to_load.deinit();
        self.allocator.destroy(self.instance_data);
        self.allocator.destroy(self);
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

fn renderImGui(user_data: *anyopaque) void {
    if (zgui.collapsingHeader("Terrain", .{})) {
        const self: *TerrainRenderPass = @ptrCast(@alignCast(user_data));

        _ = zgui.checkbox("Triplanar mapping", .{ .v = &self.terrain_render_settings.triplanar_mapping });
        _ = zgui.dragFloat("Black point", .{ .v = &self.terrain_render_settings.black_point, .speed = 0.05, .min = 0.0, .max = 1.0 });
        _ = zgui.dragFloat("White point", .{ .v = &self.terrain_render_settings.white_point, .speed = 0.05, .min = 0.0, .max = 1.0 });
    }
}

fn renderGBuffer(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Shadow Map: Terrain Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *TerrainRenderPass = @ptrCast(@alignCast(user_data));

    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();
    const z_view = zm.loadMat(camera_comps.camera.view[0..]);
    const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
    const z_proj_view = zm.mul(z_view, z_proj);

    zm.storeMat(&self.uniform_frame_data.projection_view, z_proj_view);
    zm.storeMat(&self.uniform_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
    self.uniform_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
    self.uniform_frame_data.triplanar_mapping = if (self.terrain_render_settings.triplanar_mapping) 1.0 else 0.0;
    self.uniform_frame_data.black_point = self.terrain_render_settings.black_point;
    self.uniform_frame_data.white_point = self.terrain_render_settings.white_point;

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data),
        .size = @sizeOf(UniformFrameData),
    };
    self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);

    if (self.frame_instance_count > 0) {
        const pipeline_id = IdLocal.init("terrain");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_set);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[frame_index]);
        const instance_material_buffer_index = self.renderer.getBufferBindlessIndex(self.terrain_layers_buffer);

        var start_instance_location: u32 = 0;
        for (self.quads_to_render.items) |quad_index| {
            const quad = &self.terrain_quad_tree_nodes.items[quad_index];

            const mesh_handle = self.terrain_lod_meshes.items[quad.mesh_lod];
            const mesh = self.renderer.getMesh(mesh_handle);

            if (mesh.loaded) {
                const push_constants = PushConstants{
                    .start_instance_location = start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
                    .instance_material_buffer_index = instance_material_buffer_index,
                };

                const vertex_buffers = [_][*c]graphics.Buffer{
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(graphics.ShaderSemantic.SEMANTIC_POSITION.bits)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(graphics.ShaderSemantic.SEMANTIC_TEXCOORD0.bits)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(graphics.ShaderSemantic.SEMANTIC_COLOR.bits)]].pBuffer,
                };

                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[0].mIndexCount,
                    mesh.geometry.*.pDrawArgs[0].mStartIndex,
                    mesh.geometry.*.pDrawArgs[0].mInstanceCount,
                    mesh.geometry.*.pDrawArgs[0].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[0].mStartInstance + start_instance_location,
                );
            }

            start_instance_location += 1;
        }
    }
}

fn renderShadowMap(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Shadow Map: Terrain Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *TerrainRenderPass = @ptrCast(@alignCast(user_data));

    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();

    const sun_entity = util.getSun(self.ecsu_world);
    const sun_comps = sun_entity.?.getComps(struct {
        rotation: *const fd.Rotation,
        light: *const fd.DirectionalLight,
    });

    const z_forward = zm.rotate(sun_comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 });
    const z_view = zm.lookToLh(
        zm.f32x4(camera_position[0], camera_position[1], camera_position[2], 1.0),
        z_forward * zm.f32x4s(-1.0),
        zm.f32x4(0.0, 1.0, 0.0, 0.0),
    );

    const shadow_range = sun_comps.light.shadow_range;
    const z_proj = zm.orthographicLh(shadow_range, shadow_range, -500.0, 500.0);
    const z_proj_view = zm.mul(z_view, z_proj);
    zm.storeMat(&self.shadows_uniform_frame_data.projection_view, z_proj_view);

    const data = renderer.Slice{
        .data = @ptrCast(&self.shadows_uniform_frame_data),
        .size = @sizeOf(ShadowsUniformFrameData),
    };
    self.renderer.updateBuffer(data, ShadowsUniformFrameData, self.shadows_uniform_frame_buffers[frame_index]);

    var arena_state = std.heap.ArenaAllocator.init(self.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Reset transforms, materials and draw calls array list
    self.quads_to_render.clearRetainingCapacity();
    self.quads_to_load.clearRetainingCapacity();


    {
        const player_entity = util.getPlayer(self.ecsu_world);
        const player_comps = player_entity.?.getComps(struct {
            transform: *const fd.Transform,
        });
        const player_position = player_comps.transform.getPos00();
        const player_point = [2]f32{ player_position[0], player_position[2] };

        var sector_index: u32 = 0;
        while (sector_index < lod_3_patches_total) : (sector_index += 1) {
            const lod3_node = &self.terrain_quad_tree_nodes.items[sector_index];

            collectQuadsToRenderForSector(
                self,
                player_point,
                lod_load_range,
                lod3_node,
                sector_index,
                arena,
            ) catch unreachable;
        }
    }

    self.frame_instance_count = 0;
    {
        // TODO: Batch quads together by mesh lod
        for (self.quads_to_render.items, 0..) |quad_index, instance_index| {
            const quad = &self.terrain_quad_tree_nodes.items[quad_index];

            // Add instance data
            {
                const z_world = zm.translation(quad.center[0], 0.0, quad.center[1]);
                zm.storeMat(&self.instance_data[instance_index].object_to_world, z_world);

                // TODO: Generate from quad.patch_index
                self.instance_data[instance_index].heightmap_index = self.renderer.getTextureBindlessIndex(quad.heightmap_handle.?);

                self.instance_data[instance_index].lod = quad.mesh_lod;
                self.instance_data[instance_index].padding1 = .{ 42, 42 };
            }

            self.frame_instance_count += 1;
        }
    }

    if (self.frame_instance_count > 0) {
        std.debug.assert(self.frame_instance_count <= max_instances);
        const data_slice = renderer.Slice{
            .data = @ptrCast(self.instance_data),
            .size = self.frame_instance_count * @sizeOf(InstanceData),
        };
        self.renderer.updateBuffer(data_slice, InstanceData, self.instance_data_buffers[frame_index]);

        const pipeline_id = IdLocal.init("shadows_terrain");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.shadows_descriptor_set);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[frame_index]);
        const instance_material_buffer_index = self.renderer.getBufferBindlessIndex(self.terrain_layers_buffer);

        var start_instance_location: u32 = 0;
        for (self.quads_to_render.items) |quad_index| {
            const quad = &self.terrain_quad_tree_nodes.items[quad_index];

            const mesh_handle = self.terrain_lod_meshes.items[quad.mesh_lod];
            const mesh = self.renderer.getMesh(mesh_handle);

            if (mesh.loaded) {
                const push_constants = PushConstants{
                    .start_instance_location = start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
                    .instance_material_buffer_index = instance_material_buffer_index,
                };

                const vertex_buffers = [_][*c]graphics.Buffer{
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(graphics.ShaderSemantic.SEMANTIC_POSITION.bits)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(graphics.ShaderSemantic.SEMANTIC_TEXCOORD0.bits)]].pBuffer,
                    mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intCast(graphics.ShaderSemantic.SEMANTIC_COLOR.bits)]].pBuffer,
                };

                graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[0].mIndexCount,
                    mesh.geometry.*.pDrawArgs[0].mStartIndex,
                    mesh.geometry.*.pDrawArgs[0].mInstanceCount,
                    mesh.geometry.*.pDrawArgs[0].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[0].mStartInstance + start_instance_location,
                );
            }

            start_instance_location += 1;
        }
    }

    for (self.quads_to_load.items) |quad_index| {
        const node = &self.terrain_quad_tree_nodes.items[quad_index];
        loadNodeHeightmap(
            node,
            self.renderer,
            self.world_patch_mgr,
            self.heightmap_patch_type_id,
        ) catch unreachable;
    }

    // Load high-lod patches near camera
    if (tides_math.dist3_xz(self.cam_pos_old, camera_position) > 32) {
        var lookups_old = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        var lookups_new = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        for (0..3) |lod| {
            lookups_old.clearRetainingCapacity();
            lookups_new.clearRetainingCapacity();

            const area_width = 4 * config.patch_size * @as(f32, @floatFromInt(std.math.pow(usize, 2, lod)));

            const area_old = world_patch_manager.RequestRectangle{
                .x = self.cam_pos_old[0] - area_width,
                .z = self.cam_pos_old[2] - area_width,
                .width = area_width * 2,
                .height = area_width * 2,
            };

            const area_new = world_patch_manager.RequestRectangle{
                .x = camera_position[0] - area_width,
                .z = camera_position[2] - area_width,
                .width = area_width * 2,
                .height = area_width * 2,
            };

            const lod_u4 = @as(u4, @intCast(lod));
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(self.heightmap_patch_type_id, area_old, lod_u4, &lookups_old);
            world_patch_manager.WorldPatchManager.getLookupsFromRectangle(self.heightmap_patch_type_id, area_new, lod_u4, &lookups_new);

            var i_old: u32 = 0;
            blk: while (i_old < lookups_old.items.len) {
                var i_new: u32 = 0;
                while (i_new < lookups_new.items.len) {
                    if (lookups_old.items[i_old].eql(lookups_new.items[i_new])) {
                        _ = lookups_old.swapRemove(i_old);
                        _ = lookups_new.swapRemove(i_new);
                        continue :blk;
                    }
                    i_new += 1;
                }
                i_old += 1;
            }

            const rid = self.world_patch_mgr.getRequester(IdLocal.init("terrain_quad_tree")); // HACK(Anders)
            // NOTE(Anders): HACK
            if (self.cam_pos_old[0] != -100000) {
                self.world_patch_mgr.removeLoadRequestFromLookups(rid, lookups_old.items);
            }

            self.world_patch_mgr.addLoadRequestFromLookups(rid, lookups_new.items, .medium);
        }

        self.cam_pos_old = camera_position;
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *TerrainRenderPass = @ptrCast(@alignCast(user_data));

    {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("shadows_terrain"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.shadows_descriptor_set));
    }

    {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("terrain"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.descriptor_set));
    }
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *TerrainRenderPass = @ptrCast(@alignCast(user_data));

    var params: [1]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_set, 1, @ptrCast(&params));
    }

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.shadows_uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.shadows_descriptor_set, 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *TerrainRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.shadows_descriptor_set);
}

const QuadTreeNode = struct {
    center: [2]f32,
    size: [2]f32,
    child_indices: [4]u32,
    mesh_lod: u32,
    patch_index: [2]u32,
    // TODO(gmodarelli): Do not store these here when we implement streaming
    heightmap_handle: ?renderer.TextureHandle,

    pub inline fn containsPoint(self: *QuadTreeNode, point: [2]f32) bool {
        return (point[0] > (self.center[0] - self.size[0]) and
            point[0] < (self.center[0] + self.size[0]) and
            point[1] > (self.center[1] - self.size[1]) and
            point[1] < (self.center[1] + self.size[1]));
    }

    pub inline fn nearPoint(self: *QuadTreeNode, point: [2]f32, range: f32) bool {
        const half_size = self.size[0] / 2;
        const circle_distance_x = @abs(point[0] - self.center[0]);
        const circle_distance_y = @abs(point[1] - self.center[1]);

        if (circle_distance_x > (half_size + range)) {
            return false;
        }
        if (circle_distance_y > (half_size + range)) {
            return false;
        }

        if (circle_distance_x <= (half_size)) {
            return true;
        }
        if (circle_distance_y <= (half_size)) {
            return true;
        }

        const corner_distance_sq = (circle_distance_x - half_size) * (circle_distance_x - half_size) +
            (circle_distance_y - half_size) * (circle_distance_y - half_size);

        return (corner_distance_sq <= (range * range));
    }

    pub inline fn isLoaded(self: *QuadTreeNode) bool {
        return self.heightmap_handle != null;
    }

    pub fn containedInsideChildren(self: *QuadTreeNode, point: [2]f32, range: f32, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.nearPoint(point, range)) {
            return false;
        }

        for (self.child_indices) |child_index| {
            if (child_index == std.math.maxInt(u32)) {
                return false;
            }

            var node = nodes.items[child_index];
            if (node.nearPoint(point, range)) {
                return true;
            }
        }

        return false;
    }

    pub fn areChildrenLoaded(self: *QuadTreeNode, nodes: *std.ArrayList(QuadTreeNode)) bool {
        if (!self.isLoaded()) {
            return false;
        }

        for (self.child_indices) |child_index| {
            if (child_index == std.math.maxInt(u32)) {
                return false;
            }

            var node = nodes.items[child_index];
            if (!node.isLoaded()) {
                return false;
            }
        }

        return true;
    }
};

fn loadMesh(rctx: *renderer.Renderer, path: [:0]const u8, meshes: *std.ArrayList(renderer.MeshHandle)) !void {
    const mesh_handle = rctx.loadMesh(path, IdLocal.init("pos_uv0_col")) catch unreachable;
    meshes.append(mesh_handle) catch unreachable;
}

fn loadTerrainLayer(rctx: *renderer.Renderer, name: []const u8) !TerrainLayer {
    const diffuse = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "prefabs/environment/terrain/{s}_albedo.dds",
            .{name},
        ) catch unreachable;

        break :blk rctx.loadTexture(path);
    };

    const normal = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "prefabs/environment/terrain/{s}_normal.dds",
            .{name},
        ) catch unreachable;

        break :blk rctx.loadTexture(path);
    };

    const arm = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "prefabs/environment/terrain/{s}_arm.dds",
            .{name},
        ) catch unreachable;

        break :blk rctx.loadTexture(path);
    };

    const height = blk: {
        // Generate Path
        var namebuf: [256]u8 = undefined;
        const path = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "prefabs/environment/terrain/{s}_height.dds",
            .{name},
        ) catch unreachable;

        break :blk rctx.loadTexture(path);
    };

    return .{
        .diffuse = diffuse,
        .normal = normal,
        .arm = arm,
        .height = height,
    };
}

fn loadNodeHeightmap(
    node: *QuadTreeNode,
    rctx: *renderer.Renderer,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    if (node.heightmap_handle != null) {
        return;
    }

    const lookup = world_patch_manager.PatchLookup{
        .patch_x = @as(u16, @intCast(node.patch_index[0])),
        .patch_z = @as(u16, @intCast(node.patch_index[1])),
        .lod = @as(u4, @intCast(node.mesh_lod)),
        .patch_type_id = heightmap_patch_type_id,
    };

    const patch_info = world_patch_mgr.tryGetPatch(lookup, u8);
    if (patch_info.data_opt) |data| {
        const data_slice = renderer.Slice{
            .data = @as(*anyopaque, @ptrCast(data)),
            .size = data.len,
        };

        var namebuf: [256]u8 = undefined;
        const debug_name = std.fmt.bufPrintZ(
            namebuf[0..namebuf.len],
            "lod{d}/heightmap_x{d}_z{d}",
            .{ node.mesh_lod, node.patch_index[0], node.patch_index[1] },
        ) catch unreachable;

        node.heightmap_handle = rctx.loadTextureFromMemory(65, 65, .R32_SFLOAT, data_slice, debug_name);
    }
}

fn loadResources(
    allocator: std.mem.Allocator,
    rctx: *renderer.Renderer,
    quad_tree_nodes: *std.ArrayList(QuadTreeNode),
    terrain_layers: *std.ArrayList(TerrainLayer),
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    heightmap_patch_type_id: world_patch_manager.PatchTypeId,
) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // Load terrain layers textures
    {
        const dry_ground = loadTerrainLayer(rctx, "dry_ground_rocks") catch unreachable;
        const forest_ground = loadTerrainLayer(rctx, "Wild_Grass_oiloL0_2K") catch unreachable;
        // const forest_ground = loadTerrainLayer(rctx, "Fresh_Windswept_Snow_uekmbi2dy_2K") catch unreachable;
        const rock_ground = loadTerrainLayer(rctx, "Layered_Rock_vl0fdhdo_2K") catch unreachable;
        const snow = loadTerrainLayer(rctx, "snow_02") catch unreachable;

        // NOTE: There's an implicit dependency on the order of the Splatmap here
        // - 0 dirt
        // - 1 grass
        // - 2 rock
        // - 3 snow
        terrain_layers.append(dry_ground) catch unreachable;
        terrain_layers.append(forest_ground) catch unreachable;
        terrain_layers.append(rock_ground) catch unreachable;
        terrain_layers.append(snow) catch unreachable;
    }

    // Ask the World Patch Manager to load all LOD3 for the current world extents
    const rid = world_patch_mgr.registerRequester(IdLocal.init("terrain_quad_tree"));
    const area = world_patch_manager.RequestRectangle{ .x = 0, .z = 0, .width = config.world_size_x, .height = config.world_size_z };
    var lookups = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
    world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 3, &lookups);
    world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .high);
    // Make sure all LOD3 are resident
    world_patch_mgr.tickAll();

    // Request loading all the other LODs
    lookups.clearRetainingCapacity();
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 2, &lookups);
    // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 1 &lookups);
    // world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .medium);

    // Load all LOD's heightmaps
    {
        var i: u32 = 0;
        while (i < quad_tree_nodes.items.len) : (i += 1) {
            const node = &quad_tree_nodes.items[i];
            loadNodeHeightmap(
                node,
                rctx,
                world_patch_mgr,
                heightmap_patch_type_id,
            ) catch unreachable;
        }
    }
}

fn divideQuadTreeNode(
    nodes: *std.ArrayList(QuadTreeNode),
    node: *QuadTreeNode,
) void {
    if (node.mesh_lod == 0) {
        return;
    }

    var child_index: u32 = 0;
    while (child_index < 4) : (child_index += 1) {
        const center_x = if (child_index % 2 == 0) node.center[0] - node.size[0] * 0.5 else node.center[0] + node.size[0] * 0.5;
        const center_y = if (child_index < 2) node.center[1] + node.size[1] * 0.5 else node.center[1] - node.size[1] * 0.5;
        const patch_index_x: u32 = if (child_index % 2 == 0) 0 else 1;
        const patch_index_y: u32 = if (child_index < 2) 1 else 0;

        const child_node = QuadTreeNode{
            .center = [2]f32{ center_x, center_y },
            .size = [2]f32{ node.size[0] * 0.5, node.size[1] * 0.5 },
            .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
            .mesh_lod = node.mesh_lod - 1,
            .patch_index = [2]u32{ node.patch_index[0] * 2 + patch_index_x, node.patch_index[1] * 2 + patch_index_y },
            .heightmap_handle = null,
        };

        node.child_indices[child_index] = @as(u32, @intCast(nodes.items.len));
        nodes.appendAssumeCapacity(child_node);

        std.debug.assert(node.child_indices[child_index] < nodes.items.len);
        divideQuadTreeNode(nodes, &nodes.items[node.child_indices[child_index]]);
    }
}

// Algorithm that walks a quad tree and generates a list of quad tree nodes to render
fn collectQuadsToRenderForSector(self: *TerrainRenderPass, position: [2]f32, range: f32, node: *QuadTreeNode, node_index: u32, allocator: std.mem.Allocator) !void {
    std.debug.assert(node_index != invalid_index);

    if (node.mesh_lod == 0) {
        return;
    }

    if (node.containedInsideChildren(position, range, &self.terrain_quad_tree_nodes) and node.areChildrenLoaded(&self.terrain_quad_tree_nodes)) {
        var higher_lod_node_indices: [4]u32 = .{ invalid_index, invalid_index, invalid_index, invalid_index };
        for (node.child_indices, 0..) |node_child_index, i| {
            var child_node = &self.terrain_quad_tree_nodes.items[node_child_index];
            if (child_node.nearPoint(position, range)) {
                if (child_node.mesh_lod == 1 and child_node.areChildrenLoaded(&self.terrain_quad_tree_nodes)) {
                    self.quads_to_render.appendSlice(child_node.child_indices[0..4]) catch unreachable;
                } else if (child_node.mesh_lod == 1 and !child_node.areChildrenLoaded(&self.terrain_quad_tree_nodes)) {
                    self.quads_to_render.append(node_child_index) catch unreachable;
                    self.quads_to_load.appendSlice(child_node.child_indices[0..4]) catch unreachable;
                } else if (child_node.mesh_lod > 1) {
                    higher_lod_node_indices[i] = node_child_index;
                }
            } else {
                self.quads_to_render.append(node_child_index) catch unreachable;
            }
        }

        for (higher_lod_node_indices) |higher_lod_node_index| {
            if (higher_lod_node_index != invalid_index) {
                const child_node = &self.terrain_quad_tree_nodes.items[higher_lod_node_index];
                collectQuadsToRenderForSector(self, position, range, child_node, higher_lod_node_index, allocator) catch unreachable;
            } else {
                // self.quads_to_render.append(node.child_indices[i]) catch unreachable;
            }
        }
    } else if (node.containedInsideChildren(position, range, &self.terrain_quad_tree_nodes) and !node.areChildrenLoaded(&self.terrain_quad_tree_nodes)) {
        self.quads_to_render.append(node_index) catch unreachable;
        self.quads_to_load.appendSlice(node.child_indices[0..4]) catch unreachable;
    } else {
        if (node.isLoaded()) {
            self.quads_to_render.append(node_index) catch unreachable;
        } else {
            self.quads_to_load.append(node_index) catch unreachable;
        }
    }
}
