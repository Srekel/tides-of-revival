const std = @import("std");

const ecs = @import("zflecs");
const fd = @import("../../config/flecs_data.zig");
const graphics = zforge.graphics;
const IdLocal = @import("../../core/core.zig").IdLocal;
const InstanceData = renderer_types.InstanceData;
const InstanceRootConstants = renderer_types.InstanceRootConstants;
const OpaqueSlice = util.OpaqueSlice;
const renderer = @import("../../renderer/renderer.zig");
const renderer_types = @import("../../renderer/types.zig");
const resource_loader = zforge.resource_loader;
const util = @import("../../util.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const zm = @import("zmath");
const ztracy = @import("ztracy");

pub const UniformFrameData = struct {
    projection: [16]f32,
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
    depth_buffer_parameters: [4]f32,
    lights_buffer_index: u32,
    lights_count: u32,
    time: f32,
    caustics_texture_index: u32,
    fog_color: [3]f32,
    fog_density: f32,

    // Water material data
    water_fog_color: [3]f32,
    water_density: f32,
    normal_map_1_params: [4]f32,
    normal_map_2_params: [4]f32,
    normal_map_1_texture_index: u32 = renderer_types.InvalidResourceIndex,
    normal_map_2_texture_index: u32 = renderer_types.InvalidResourceIndex,
    surface_roughness: f32,
    refraction_strength: f32,
};

const max_instances = 1024;

pub const WaterPass = struct {
    allocator: std.mem.Allocator,
    renderer: *renderer.Renderer,

    ocean_tile_mesh_handle: renderer.LegacyMeshHandle,
    ocean_tile_mesh: renderer.LegacyMesh,
    normal_map_texture: renderer.TextureHandle = undefined,
    caustics_texture: renderer.TextureHandle = undefined,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    water_descriptor_sets: [*c]graphics.DescriptorSet,
    rt_copy_descriptor_sets: [*c]graphics.DescriptorSet,

    instance_data: std.ArrayList(InstanceData),
    instance_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    water_fog_color: [3]f32,
    water_density: f32,
    refraction_strength: f32,
    surface_roughness: f32 = 0.2,
    normal_map_1_params: [4]f32 = [4]f32{ 0.2, 0.7, -0.12, 0.5 },
    normal_map_2_params: [4]f32 = [4]f32{ 0.1, -0.42, 0.33, 0.5 },

    pub fn init(self: *@This(), rctx: *renderer.Renderer, allocator: std.mem.Allocator) void {
        self.allocator = allocator;
        self.renderer = rctx;

        self.uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        self.instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createBindlessBuffer(max_instances * @sizeOf(InstanceData), "Water Instance Data");
            }

            break :blk buffers;
        };

        self.instance_data = std.ArrayList(InstanceData).init(self.allocator);

        self.ocean_tile_mesh_handle = rctx.loadLegacyMesh("prefabs/primitives/primitive_plane.bin", IdLocal.init("pos_uv0_nor_tan_col")) catch unreachable;
        self.ocean_tile_mesh = rctx.getLegacyMesh(self.ocean_tile_mesh_handle);
        self.normal_map_texture = rctx.loadTexture("prefabs/environment/water/water_normal.dds");
        self.caustics_texture = rctx.loadTexture("prefabs/environment/water/T_Animated_WaterCaustics_1K_overlay.dds");

        self.water_fog_color = [3]f32{ 14.0 / 255.0, 55.0 / 255.0, 125.0 / 255.0 };
        self.water_density = 0.3;
        self.refraction_strength = 0.15;
        self.surface_roughness = 0.2;
        self.normal_map_1_params = [4]f32{ 0.2, 0.7, -0.12, 0.5 };
        self.normal_map_2_params = [4]f32{ 0.1, -0.42, 0.33, 0.5 };
    }

    pub fn destroy(self: *@This()) void {
        self.instance_data.deinit();
    }

    pub fn renderImGui(self: *@This()) void {
        if (zgui.collapsingHeader("Water", .{})) {
            _ = zgui.colorEdit3("Water Fog Color", .{ .col = &self.water_fog_color });
            _ = zgui.dragFloat("Water Density", .{ .cfmt = "%.2f", .v = &self.water_density, .min = 0.0, .max = 1.0, .speed = 0.01 });
            _ = zgui.dragFloat("Refraction Strength", .{ .cfmt = "%.2f", .v = &self.refraction_strength, .min = 0.0, .max = 1.0, .speed = 0.01 });
        }
    }

    pub fn render(self: *@This(), cmd_list: [*c]graphics.Cmd, render_view: renderer.RenderView) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Water Pass", 0x00_ff_ff_00);
        defer trazy_zone.End();
        const frame_index = self.renderer.frame_index;

        // Copy Scene Color and Depth
        {
            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.renderer.scene_color_copy, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.renderer.depth_buffer_copy, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 2;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.renderer.scene_color_copy;
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            bind_render_targets_desc.mRenderTargets[1] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[1].pRenderTarget = self.renderer.depth_buffer_copy;
            bind_render_targets_desc.mRenderTargets[1].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            const pipeline_id = IdLocal.init("copy_scene_color_and_depth");
            const pipeline = self.renderer.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.rt_copy_descriptor_sets);
            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.renderer.window.frame_buffer_size[0]), @floatFromInt(self.renderer.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]));
            graphics.cmdDraw(cmd_list, 3, 0);

            var output_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.renderer.scene_color, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.renderer.scene_color_copy, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.renderer.depth_buffer_copy, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));
        }

        // Render Water
        {
            var frame_data = std.mem.zeroes(UniformFrameData);
            zm.storeMat(&frame_data.projection, render_view.projection);
            zm.storeMat(&frame_data.projection_view, render_view.view_projection);
            zm.storeMat(&frame_data.projection_view_inverted, render_view.view_projection_inverse);
            frame_data.camera_position = [4]f32{ render_view.position[0], render_view.position[1], render_view.position[2], 1.0 };
            const near = render_view.near_plane;
            const far = render_view.far_plane;
            frame_data.depth_buffer_parameters = [4]f32{ far / near - 1.0, 1, (1 / near - 1 / far), 1 / far };
            frame_data.time = @floatCast(self.renderer.time);
            frame_data.lights_buffer_index = self.renderer.getBufferBindlessIndex(self.renderer.light_buffer.buffer);
            frame_data.lights_count = self.renderer.light_buffer.element_count;
            frame_data.fog_color = self.renderer.height_fog_settings.color;
            frame_data.fog_density = self.renderer.height_fog_settings.density;
            frame_data.water_fog_color = self.water_fog_color;
            frame_data.caustics_texture_index = self.renderer.getTextureBindlessIndex(self.caustics_texture);
            frame_data.normal_map_1_texture_index = self.renderer.getTextureBindlessIndex(self.normal_map_texture);
            frame_data.normal_map_2_texture_index = self.renderer.getTextureBindlessIndex(self.normal_map_texture);
            frame_data.surface_roughness = self.surface_roughness;
            frame_data.water_density = self.water_density;
            frame_data.normal_map_1_params = self.normal_map_1_params;
            frame_data.normal_map_2_params = self.normal_map_2_params;
            frame_data.refraction_strength = self.refraction_strength;

            // Update Uniform Frame Buffer
            {
                const data = OpaqueSlice{
                    .data = @ptrCast(&frame_data),
                    .size = @sizeOf(UniformFrameData),
                };
                self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers[frame_index]);
            }

            self.instance_data.clearRetainingCapacity();

            for (self.renderer.ocean_tiles.items) |ocean_tile| {
                // TODO: Check for visibility
                // const aabb_center = zm.loadArr3w(self.ocean_tile_mesh.geometry.*.mAabbCenter, 1.0);
                // zm.storeArr3(&ocean_tile.bounding_sphere_center, zm.mul(aabb_center, ocean_tile.world));
                // ocean_tile.bounding_sphere_radius = self.ocean_tile_mesh.geometry.*.mRadius * ocean_tile.scale;

                var instance_data = std.mem.zeroes(InstanceData);
                zm.storeMat(&instance_data.object_to_world, ocean_tile.world);
                // zm.storeMat(&instance_data.world_to_object, zm.inverse(ocean_tile.world));
                self.instance_data.append(instance_data) catch unreachable;
            }

            if (self.instance_data.items.len > 0) {
                const instance_data_slice = OpaqueSlice{
                    .data = @ptrCast(self.instance_data.items),
                    .size = self.instance_data.items.len * @sizeOf(InstanceData),
                };
                self.renderer.updateBuffer(instance_data_slice, 0, InstanceData, self.instance_data_buffers[frame_index]);

                const pipeline_id = IdLocal.init("water");
                const pipeline = self.renderer.getPSO(pipeline_id);
                const root_signature = self.renderer.getRootSignature(pipeline_id);
                const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                std.debug.assert(root_constant_index != renderer_types.InvalidResourceIndex);

                graphics.cmdBindPipeline(cmd_list, pipeline);
                graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.water_descriptor_sets);

                var input_barriers = [_]graphics.RenderTargetBarrier{
                    graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_DEPTH_READ),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

                var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
                bind_render_targets_desc.mRenderTargetCount = 1;
                bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
                bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.renderer.scene_color;
                bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;
                bind_render_targets_desc.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
                bind_render_targets_desc.mDepthStencil.pDepthStencil = self.renderer.depth_buffer;
                bind_render_targets_desc.mDepthStencil.mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;

                graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

                graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.renderer.window.frame_buffer_size[0]), @floatFromInt(self.renderer.window.frame_buffer_size[1]), 0.0, 1.0);
                graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]));

                const mesh = &self.ocean_tile_mesh;
                const vertex_layout = self.renderer.getVertexLayout(mesh.vertex_layout_id).?;
                const vertex_buffer_count_max = 12; // TODO(gmodarelli): Use MAX_SEMANTICS
                var vertex_buffers: [vertex_buffer_count_max][*c]graphics.Buffer = undefined;

                for (0..vertex_layout.mAttribCount) |attribute_index| {
                    const buffer = mesh.geometry.*.__union_field1.__struct_field1.pVertexBuffers[mesh.buffer_layout_desc.mSemanticBindings[@intCast(vertex_layout.mAttribs[attribute_index].mSemantic.bits)]];
                    vertex_buffers[attribute_index] = buffer;
                }

                graphics.cmdBindVertexBuffer(cmd_list, vertex_layout.mAttribCount, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
                graphics.cmdBindIndexBuffer(cmd_list, mesh.geometry.*.__union_field1.__struct_field1.pIndexBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);

                const push_constants = InstanceRootConstants{
                    .start_instance_location = 0,
                    .instance_data_buffer_index = self.renderer.getBufferBindlessIndex(self.instance_data_buffers[frame_index]),
                    .instance_material_buffer_index = 0,
                };

                graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
                graphics.cmdDrawIndexedInstanced(
                    cmd_list,
                    mesh.geometry.*.pDrawArgs[0].mIndexCount,
                    mesh.geometry.*.pDrawArgs[0].mStartIndex,
                    mesh.geometry.*.pDrawArgs[0].mInstanceCount * @as(u32, @intCast(self.instance_data.items.len)),
                    mesh.geometry.*.pDrawArgs[0].mVertexOffset,
                    mesh.geometry.*.pDrawArgs[0].mStartInstance + 0,
                );

                var output_barriers = [_]graphics.RenderTargetBarrier{
                    graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_DEPTH_READ, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));
            }
        }
    }

    pub fn createDescriptorSets(self: *@This()) void {
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;

        var root_signature = self.renderer.getRootSignature(IdLocal.init("water"));
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.water_descriptor_sets));

        root_signature = self.renderer.getRootSignature(IdLocal.init("copy_scene_color_and_depth"));
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.rt_copy_descriptor_sets));
    }

    pub fn prepareDescriptorSets(self: *@This()) void {
        var params: [3]graphics.DescriptorData = undefined;

        for (0..renderer.Renderer.data_buffer_count) |i| {
            var uniform_frame_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbFrame";
            params[0].__union_field3.ppBuffers = @ptrCast(&uniform_frame_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_scene_color";
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color_copy.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "g_depth_buffer";
            params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer_copy.*.pTexture);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.water_descriptor_sets, params.len, @ptrCast(&params));

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "g_scene_color";
            params[0].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "g_depth_buffer";
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer.*.pTexture);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.rt_copy_descriptor_sets, 2, @ptrCast(&params));
        }
    }

    pub fn unloadDescriptorSets(self: *@This()) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.water_descriptor_sets);
        graphics.removeDescriptorSet(self.renderer.renderer, self.rt_copy_descriptor_sets);
    }
};
