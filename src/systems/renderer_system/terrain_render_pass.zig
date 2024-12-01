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

const lod_load_range = 4300;
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

const TerrainMaterial = struct {
    layers: [4]TerrainLayer,
};

const InstanceData = struct {
    object_to_world: [16]f32,
    heightmap_index: u32,
    normalmap_index: u32,
    lod: u32,
    padding1: u32,
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
};

const NormalInfo = struct {
    heightmap_handle: renderer.TextureHandle,
    normalmap_handle: renderer.TextureHandle,
    texture_resolution: u32,
    lod: u32,
};

const NormalFromHeightRootConstants = struct {
    heightmap_index: u32,
    normalmap_index: u32,
    texture_resolution: u32,
    lod: u32,
};

pub const TerrainRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    world_patch_mgr: *world_patch_manager.WorldPatchManager,
    terrain_render_settings: TerrainRenderSettings,
    terrain_material: TerrainMaterial,

    shadows_uniform_frame_data: ShadowsUniformFrameData,
    shadows_uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    shadows_descriptor_set: [*c]graphics.DescriptorSet,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    terrain_material_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_set: [*c]graphics.DescriptorSet,

    frame_instance_count: u32,
    instance_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    instance_data: *[max_instances]InstanceData,

    terrain_quad_tree_nodes: std.ArrayList(QuadTreeNode),
    terrain_lod_meshes: std.ArrayList(renderer.MeshHandle),
    quads_to_render: std.ArrayList(u32),
    quads_to_load: std.ArrayList(u32),
    normals_to_generate: std.ArrayList(NormalInfo),

    heightmap_patch_type_id: world_patch_manager.PatchTypeId,

    cam_pos_old: [3]f32 = .{ -100000, 0, -100000 }, // NOTE(Anders): Assumes only one camera

    pub fn init(self: *TerrainRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, world_patch_mgr: *world_patch_manager.WorldPatchManager, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.ecsu_world = ecsu_world;
        self.renderer = rctx;
        self.world_patch_mgr = world_patch_mgr;
        self.terrain_render_settings = .{
            .triplanar_mapping = true,
            .black_point = 0,
            .white_point = 1.0,
        };
        self.frame_instance_count = 0;
        self.cam_pos_old = .{ -100000, 0, -100000 }; // NOTE(Anders): Assumes only one camera

        // TODO(gmodarelli): This is just enough for a single sector, but it's good for testing
        const max_quad_tree_nodes: usize = 85 * lod_3_patches_total;
        self.terrain_quad_tree_nodes = std.ArrayList(QuadTreeNode).initCapacity(self.allocator, max_quad_tree_nodes) catch unreachable;
        self.quads_to_render = std.ArrayList(u32).init(self.allocator);
        self.quads_to_load = std.ArrayList(u32).init(self.allocator);
        self.normals_to_generate = std.ArrayList(NormalInfo).init(self.allocator);

        // Create initial sectors
        {
            const patch_half_size = @as(f32, @floatFromInt(config.largest_patch_width)) / 2.0;
            var patch_y: u32 = 0;
            while (patch_y < lod_3_patches_side) : (patch_y += 1) {
                var patch_x: u32 = 0;
                while (patch_x < lod_3_patches_side) : (patch_x += 1) {
                    self.terrain_quad_tree_nodes.appendAssumeCapacity(.{
                        .center = [2]f32{
                            @as(f32, @floatFromInt(patch_x * config.largest_patch_width)) + patch_half_size,
                            @as(f32, @floatFromInt(patch_y * config.largest_patch_width)) + patch_half_size,
                        },
                        .size = [2]f32{ patch_half_size, patch_half_size },
                        .child_indices = [4]u32{ invalid_index, invalid_index, invalid_index, invalid_index },
                        .mesh_lod = 3,
                        .patch_index = [2]u32{ patch_x, patch_y },
                        .heightmap_handle = null,
                        .normalmap_handle = null,
                    });
                }
            }

            std.debug.assert(self.terrain_quad_tree_nodes.items.len == lod_3_patches_total);

            var sector_index: u32 = 0;
            while (sector_index < lod_3_patches_total) : (sector_index += 1) {
                const node = &self.terrain_quad_tree_nodes.items[sector_index];
                divideQuadTreeNode(&self.terrain_quad_tree_nodes, node);
            }
        }

        self.heightmap_patch_type_id = world_patch_mgr.getPatchTypeId(config.patch_type_heightmap);
        self.loadTerrainResources() catch unreachable;

        // Create instance buffers.
        self.instance_data = allocator.create([max_instances]InstanceData) catch unreachable;
        self.instance_data_buffers = blk: {
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

        self.shadows_uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ShadowsUniformFrameData);
            }

            break :blk buffers;
        };

        self.uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        self.terrain_material_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = self.renderer.createUniformBuffer(TerrainMaterial);
            }

            break :blk buffers;
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_gbuffer_pass_fn = renderGBuffer,
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
        self.normals_to_generate.deinit();
        self.allocator.destroy(self.instance_data);
        self.allocator.destroy(self);
    }

    fn loadTerrainResources(self: *TerrainRenderPass) !void {
        var arena_state = std.heap.ArenaAllocator.init(self.allocator);
        defer arena_state.deinit();
        const arena = arena_state.allocator();

        // Load terrain meshes
        self.loadTerrainMeshes() catch unreachable;

        // Load terrain layers textures
        self.loadTerrainMaterial() catch unreachable;

        // Ask the World Patch Manager to load all LOD3 for the current world extents
        const rid = self.world_patch_mgr.registerRequester(IdLocal.init("terrain_quad_tree"));
        const area = world_patch_manager.RequestRectangle{ .x = 0, .z = 0, .width = config.world_size_x, .height = config.world_size_z };
        var lookups = std.ArrayList(world_patch_manager.PatchLookup).initCapacity(arena, 1024) catch unreachable;
        world_patch_manager.WorldPatchManager.getLookupsFromRectangle(self.heightmap_patch_type_id, area, 3, &lookups);
        self.world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .high);
        // Make sure all LOD3 are resident
        self.world_patch_mgr.tickAll();

        // Request loading all the other LODs
        lookups.clearRetainingCapacity();
        // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 2, &lookups);
        // world_patch_manager.WorldPatchManager.getLookupsFromRectangle(heightmap_patch_type_id, area, 1 &lookups);
        // world_patch_mgr.addLoadRequestFromLookups(rid, lookups.items, .medium);

        // Load all LOD's heightmaps
        {
            var i: u32 = 0;
            while (i < self.terrain_quad_tree_nodes.items.len) : (i += 1) {
                const node = &self.terrain_quad_tree_nodes.items[i];
                self.loadNodeHeightmap(node) catch unreachable;
            }
        }
    }

    fn loadTerrainMeshes(self: *TerrainRenderPass) !void {
        self.terrain_lod_meshes = std.ArrayList(renderer.MeshHandle).init(self.allocator);
        self.loadTerrainMesh("prefabs/environment/terrain/terrain_patch_0.bin") catch unreachable;
        self.loadTerrainMesh("prefabs/environment/terrain/terrain_patch_1.bin") catch unreachable;
        self.loadTerrainMesh("prefabs/environment/terrain/terrain_patch_2.bin") catch unreachable;
        self.loadTerrainMesh("prefabs/environment/terrain/terrain_patch_3.bin") catch unreachable;
    }

    fn loadTerrainMesh(self: *TerrainRenderPass, path: [:0]const u8) !void {
        const mesh_handle = self.renderer.loadMesh(path, IdLocal.init("pos_uv0_col")) catch unreachable;
        self.terrain_lod_meshes.append(mesh_handle) catch unreachable;
    }

    fn loadTerrainMaterial(self: *TerrainRenderPass) !void {
        self.terrain_material.layers[0] = self.loadTerrainLayer("dry_ground_rocks") catch unreachable;
        self.terrain_material.layers[1] = self.loadTerrainLayer("Wild_Grass_oiloL0_2K") catch unreachable;
        self.terrain_material.layers[2] = self.loadTerrainLayer("Layered_Rock_vl0fdhdo_2K") catch unreachable;
        self.terrain_material.layers[3] = self.loadTerrainLayer("snow_02") catch unreachable;
    }

    fn loadTerrainLayer(self: *TerrainRenderPass, name: []const u8) !TerrainLayer {
        const diffuse = blk: {
            // Generate Path
            var namebuf: [256]u8 = undefined;
            const path = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "prefabs/environment/terrain/{s}_albedo.dds",
                .{name},
            ) catch unreachable;

            break :blk self.renderer.loadTexture(path);
        };

        const normal = blk: {
            // Generate Path
            var namebuf: [256]u8 = undefined;
            const path = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "prefabs/environment/terrain/{s}_normal.dds",
                .{name},
            ) catch unreachable;

            break :blk self.renderer.loadTexture(path);
        };

        const arm = blk: {
            // Generate Path
            var namebuf: [256]u8 = undefined;
            const path = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "prefabs/environment/terrain/{s}_arm.dds",
                .{name},
            ) catch unreachable;

            break :blk self.renderer.loadTexture(path);
        };

        const height = blk: {
            // Generate Path
            var namebuf: [256]u8 = undefined;
            const path = std.fmt.bufPrintZ(
                namebuf[0..namebuf.len],
                "prefabs/environment/terrain/{s}_height.dds",
                .{name},
            ) catch unreachable;

            break :blk self.renderer.loadTexture(path);
        };

        return .{
            .diffuse = diffuse,
            .normal = normal,
            .arm = arm,
            .height = height,
        };
    }

    fn loadNodeHeightmap(self: *TerrainRenderPass, node: *QuadTreeNode) !void {
        if (node.heightmap_handle != null) {
            return;
        }

        const lookup = world_patch_manager.PatchLookup{
            .patch_x = @as(u16, @intCast(node.patch_index[0])),
            .patch_z = @as(u16, @intCast(node.patch_index[1])),
            .lod = @as(u4, @intCast(node.mesh_lod)),
            .patch_type_id = self.heightmap_patch_type_id,
        };

        const patch_info = self.world_patch_mgr.tryGetPatch(lookup, u8);
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

            node.heightmap_handle = self.renderer.loadTextureFromMemory(65, 65, .R32_SFLOAT, data_slice, debug_name);

            if (node.normalmap_handle != null) {
                return;
            }

            // Create normal map for this node's heightmap
            {
                var desc = std.mem.zeroes(graphics.TextureDesc);
                desc.mWidth = 65;
                desc.mHeight = 65;
                desc.mDepth = 1;
                desc.mArraySize = 1;
                desc.mMipLevels = 1;
                desc.mFormat = graphics.TinyImageFormat.R10G10B10A2_UNORM;
                desc.mStartState = graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS;
                desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
                desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                desc.bBindless = true;

                var normal_namebuf: [256]u8 = undefined;
                const normal_debug_name = std.fmt.bufPrintZ(
                    normal_namebuf[0..normal_namebuf.len],
                    "lod{d}/normalmap_x{d}_z{d}",
                    .{ node.mesh_lod, node.patch_index[0], node.patch_index[1] },
                ) catch unreachable;

                desc.pName = normal_debug_name;
                node.normalmap_handle = self.renderer.createTexture(desc);
            }

            const normal_info = NormalInfo{
                .heightmap_handle = node.heightmap_handle.?,
                .normalmap_handle = node.normalmap_handle.?,
                .texture_resolution = 65,
                .lod = node.mesh_lod,
            };

            self.normals_to_generate.append(normal_info) catch unreachable;
        }
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

    // Update frame buffer
    {
        var uniform_frame_data = std.mem.zeroes(UniformFrameData);
        zm.storeMat(&uniform_frame_data.projection_view, z_proj_view);
        zm.storeMat(&uniform_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
        uniform_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
        uniform_frame_data.triplanar_mapping = if (self.terrain_render_settings.triplanar_mapping) 1.0 else 0.0;
        uniform_frame_data.black_point = self.terrain_render_settings.black_point;
        uniform_frame_data.white_point = self.terrain_render_settings.white_point;

        const data = renderer.Slice{
            .data = @ptrCast(&uniform_frame_data),
            .size = @sizeOf(UniformFrameData),
        };
        self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);
    }

    // Update material buffer
    {
        var terrain_material_data: [4]TerrainLayerMaterial = undefined;
        for (self.terrain_material.layers, 0..) |layer, i| {
            terrain_material_data[i] = .{
                .diffuse_index = self.renderer.getTextureBindlessIndex(layer.diffuse),
                .normal_index = self.renderer.getTextureBindlessIndex(layer.normal),
                .arm_index = self.renderer.getTextureBindlessIndex(layer.arm),
                .height_index = self.renderer.getTextureBindlessIndex(layer.height),
            };
        }

        const data = renderer.Slice{
            .data = @ptrCast(&terrain_material_data),
            .size = @sizeOf(TerrainMaterial),
        };
        self.renderer.updateBuffer(data, TerrainMaterial, self.terrain_material_buffers[frame_index]);
    }

    if (self.frame_instance_count > 0) {
        const pipeline_id = IdLocal.init("terrain");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_set);

        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));

        const instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[frame_index]);

        var start_instance_location: u32 = 0;
        for (self.quads_to_render.items) |quad_index| {
            const quad = &self.terrain_quad_tree_nodes.items[quad_index];

            const mesh_handle = self.terrain_lod_meshes.items[quad.mesh_lod];
            const mesh = self.renderer.getMesh(mesh_handle);

            if (mesh.loaded) {
                const push_constants = PushConstants{
                    .start_instance_location = start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
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

    if (self.normals_to_generate.items.len > 0) {
        const pipeline_id = IdLocal.init("normal_from_height");
        const pipeline = self.renderer.getPSO(pipeline_id);
        const root_signature = self.renderer.getRootSignature(pipeline_id);
        const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
        std.debug.assert(root_constant_index != std.math.maxInt(u32));
        graphics.cmdBindPipeline(cmd_list, pipeline);

        for (self.normals_to_generate.items) |normals_info| {
            const heightmap_texture_index = self.renderer.getTextureBindlessIndex(normals_info.heightmap_handle);
            const normalmap_texture_index = self.renderer.getTextureBindlessIndex(normals_info.normalmap_handle);
            const push_constants = NormalFromHeightRootConstants{
                .heightmap_index = heightmap_texture_index,
                .normalmap_index = normalmap_texture_index,
                .texture_resolution = normals_info.texture_resolution,
                .lod = normals_info.lod,
            };

            graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
            // 9 == 65 / 8 + 1
            graphics.cmdDispatch(cmd_list, 9, 9, 1);

            const normalmap_texture = self.renderer.getTexture(normals_info.normalmap_handle);
            const output_barrier = [_]graphics.TextureBarrier{
                graphics.TextureBarrier.init(normalmap_texture, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, output_barrier.len, @constCast(&output_barrier), 0, null);
        }
    }

    // Reset transforms, materials and draw calls array list
    self.quads_to_render.clearRetainingCapacity();
    self.quads_to_load.clearRetainingCapacity();
    self.normals_to_generate.clearRetainingCapacity();

    {
        const camera_point = [2]f32{ camera_position[0], camera_position[2] };

        var sector_index: u32 = 0;
        while (sector_index < lod_3_patches_total) : (sector_index += 1) {
            const lod3_node = &self.terrain_quad_tree_nodes.items[sector_index];

            collectQuadsToRenderForSector(
                self,
                camera_point,
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
                self.instance_data[instance_index].normalmap_index = self.renderer.getTextureBindlessIndex(quad.normalmap_handle.?);

                self.instance_data[instance_index].lod = quad.mesh_lod;
                self.instance_data[instance_index].padding1 = 42;
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

        var start_instance_location: u32 = 0;
        for (self.quads_to_render.items) |quad_index| {
            const quad = &self.terrain_quad_tree_nodes.items[quad_index];

            const mesh_handle = self.terrain_lod_meshes.items[quad.mesh_lod];
            const mesh = self.renderer.getMesh(mesh_handle);

            if (mesh.loaded) {
                const push_constants = PushConstants{
                    .start_instance_location = start_instance_location,
                    .instance_data_buffer_index = instance_data_buffer_index,
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
        self.loadNodeHeightmap(node) catch unreachable;
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

    var params: [2]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        var material_buffer = self.renderer.getBuffer(self.terrain_material_buffers[i]);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "cbMaterial";
        params[1].__union_field3.ppBuffers = @ptrCast(&material_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_set, params.len, @ptrCast(&params));
        // NOTE: Shadows don't need the material buffer
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
    normalmap_handle: ?renderer.TextureHandle,

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
            .normalmap_handle = null,
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
