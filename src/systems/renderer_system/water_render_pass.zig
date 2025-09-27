const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const renderer_types = @import("../../renderer/types.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const OpaqueSlice = util.OpaqueSlice;
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;
const InstanceData = renderer_types.InstanceData;
const InstanceRootConstants = renderer_types.InstanceRootConstants;

pub const UniformFrameData = struct {
    projection: [16]f32,
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
    depth_buffer_parameters: [4]f32,
    time: f32,
};

pub const UniformLightData = struct {
    // TODO(gmodarelli): Use light buffers
    sun_color_intensity: [4]f32 = [4]f32{ 0.0, 0.0, 0.0, 0.0 },
    sun_direction: [3]f32 = [3]f32{ 0.0, 0.0, 0.0 },
    _padding1: f32 = 42.0,
};

pub const WaterMaterialInstance = struct {
    absorption_color: [3]f32,
    absorption_coefficient: f32,
    surface_roughness: f32,
    surface_opacity: f32,

    // TODO(gmodarelli): Should we expose these textures in ImGUI?
    normal_map_1_texture: renderer.TextureHandle = undefined,
    normal_map_1_tiling: f32 = 0.2,
    normal_map_1_direction: [2]f32 = [2]f32{ 0.7, -0.12 },
    normal_map_1_intensity: f32 = 0.5,

    normal_map_2_texture: renderer.TextureHandle = undefined,
    normal_map_2_tiling: f32 = 0.1,
    normal_map_2_direction: [2]f32 = [2]f32{ -0.42, 0.33 },
    normal_map_2_intensity: f32 = 0.5,
};

pub const WaterMaterial = struct {
    absorption_color: [3]f32,
    absorption_coefficient: f32,

    normal_map_1_texture_index: u32 = renderer_types.InvalidResourceIndex,
    normal_map_2_texture_index: u32 = renderer_types.InvalidResourceIndex,
    surface_roughness: f32,
    surface_opacity: f32,

    normal_map_1_params: [4]f32,
    normal_map_2_params: [4]f32,
};

const max_instances = 1024;

pub const WaterRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,
    query_water: *ecs.query_t,

    uniform_frame_data: UniformFrameData,
    uniform_light_data: UniformLightData,
    water_material_instance: WaterMaterialInstance,

    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    uniform_light_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    water_descriptor_sets: [*c]graphics.DescriptorSet,
    rt_copy_descriptor_sets: [*c]graphics.DescriptorSet,

    instance_data: std.ArrayList(InstanceData),
    instance_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    material_data: std.ArrayList(WaterMaterial),
    material_data_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    pub fn init(self: *WaterRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        const uniform_light_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformLightData);
            }

            break :blk buffers;
        };

        const instance_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = max_instances * @sizeOf(InstanceData),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, false, "Water Instance Data");
            }

            break :blk buffers;
        };

        const material_data_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = OpaqueSlice{
                    .data = null,
                    .size = max_instances * @sizeOf(WaterMaterial),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, false, "Water Material Data");
            }

            break :blk buffers;
        };

        const query_water = ecs.query_init(ecsu_world.world, &.{
            .entity = ecs.new_entity(ecsu_world.world, "query_water"),
            .terms = [_]ecs.term_t{
                .{ .id = ecs.id(fd.Transform), .inout = .In },
                .{ .id = ecs.id(fd.Water), .inout = .In },
                .{ .id = ecs.id(fd.Scale), .inout = .In },
            } ++ ecs.array(ecs.term_t, ecs.FLECS_TERM_COUNT_MAX - 3),
        }) catch unreachable;

        const water_normal_handle = rctx.loadTexture("prefabs/environment/water/water_normal.dds");
        const water_material_instance = WaterMaterialInstance{
            .absorption_color = [3]f32{ 0.12, 0.0, 0.0 },
            .absorption_coefficient = 0.8,
            .surface_roughness = 0.2,
            .surface_opacity = 0.8,

            .normal_map_1_texture = water_normal_handle,
            .normal_map_2_texture = water_normal_handle,
        };

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .water_material_instance = water_material_instance,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_light_data = std.mem.zeroes(UniformLightData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .uniform_light_buffers = uniform_light_buffers,
            .water_descriptor_sets = undefined,
            .rt_copy_descriptor_sets = undefined,
            .instance_data = std.ArrayList(InstanceData).init(allocator),
            .instance_data_buffers = instance_data_buffers,
            .material_data = std.ArrayList(WaterMaterial).init(allocator),
            .material_data_buffers = material_data_buffers,
            .query_water = query_water,
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_water_pass_fn = render,
            .render_imgui_fn = renderImGui,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *WaterRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);

        unloadDescriptorSets(@ptrCast(self));
        self.instance_data.deinit();
        self.material_data.deinit();
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

fn renderImGui(user_data: *anyopaque) void {
    if (zgui.collapsingHeader("Water", .{})) {
        const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));

        _ = zgui.colorEdit3("Absorption Color", .{ .col = &self.water_material_instance.absorption_color });
        _ = zgui.dragFloat("Absorption Coefficient", .{ .v = &self.water_material_instance.absorption_coefficient, .speed = 0.05, .min = 0.0, .max = 1.0 });
        _ = zgui.dragFloat("Surface Roughness", .{ .v = &self.water_material_instance.surface_roughness, .speed = 0.01, .min = 0.04, .max = 1.0 });
        _ = zgui.dragFloat("Surface Opacity", .{ .v = &self.water_material_instance.surface_opacity, .speed = 0.01, .min = 0.0, .max = 1.0 });
        _ = zgui.dragFloat("Water 1 Tiling", .{ .v = &self.water_material_instance.normal_map_1_tiling, .speed = 0.01, .min = 0.0, .max = 10.0 });
        _ = zgui.dragFloat("Water 1 Intensity", .{ .v = &self.water_material_instance.normal_map_1_intensity, .speed = 0.01, .min = 0.0, .max = 1.0 });
        _ = zgui.dragFloat2("Water 1 Direction", .{ .v = &self.water_material_instance.normal_map_1_direction, .speed = 0.01, .min = -1.0, .max = 1.0 });
        _ = zgui.dragFloat("Water 2 Tiling", .{ .v = &self.water_material_instance.normal_map_2_tiling, .speed = 0.01, .min = 0.0, .max = 10.0 });
        _ = zgui.dragFloat("Water 2 Intensity", .{ .v = &self.water_material_instance.normal_map_2_intensity, .speed = 0.01, .min = 0.0, .max = 1.0 });
        _ = zgui.dragFloat2("Water 2 Direction", .{ .v = &self.water_material_instance.normal_map_2_direction, .speed = 0.01, .min = -1.0, .max = 1.0 });
    }
}

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Water Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));
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
        var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
        const camera_comps = camera_entity.getComps(struct {
            camera: *const fd.Camera,
            transform: *const fd.Transform,
        });
        const camera_position = camera_comps.transform.getPos00();
        const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
        const z_proj_view = zm.loadMat(camera_comps.camera.view_projection[0..]);

        zm.storeMat(&self.uniform_frame_data.projection, z_proj);
        zm.storeMat(&self.uniform_frame_data.projection_view, z_proj_view);
        zm.storeMat(&self.uniform_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
        self.uniform_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };
        const near = camera_comps.camera.near;
        const far = camera_comps.camera.far;
        self.uniform_frame_data.depth_buffer_parameters = [4]f32{ far / near - 1.0, 1, (1 / near - 1 / far), 1 / far };
        self.uniform_frame_data.time = @floatCast(self.renderer.time);

        // Update Uniform Frame Buffer
        {
            const data = OpaqueSlice{
                .data = @ptrCast(&self.uniform_frame_data),
                .size = @sizeOf(UniformFrameData),
            };
            self.renderer.updateBuffer(data, 0, UniformFrameData, self.uniform_frame_buffers[frame_index]);
        }

        const sun_entity = util.getSun(self.ecsu_world);
        const sun_light = sun_entity.?.get(fd.DirectionalLight);
        const sun_rotation = sun_entity.?.get(fd.Rotation);
        const z_sun_forward = zm.normalize4(zm.rotate(sun_rotation.?.asZM(), zm.Vec{ 0, 0, 1, 0 }));
        zm.storeArr3(&self.uniform_light_data.sun_direction, z_sun_forward);
        self.uniform_light_data.sun_color_intensity = [4]f32{ sun_light.?.color.r, sun_light.?.color.g, sun_light.?.color.b, sun_light.?.intensity };

        // Update Light Buffer
        {
            const data = OpaqueSlice{
                .data = @ptrCast(&self.uniform_light_data),
                .size = @sizeOf(UniformLightData),
            };
            self.renderer.updateBuffer(data, 0, UniformLightData, self.uniform_light_buffers[frame_index]);
        }

        self.instance_data.clearRetainingCapacity();

        var mesh: renderer.LegacyMesh = undefined;
        var first_iteration = true;
        var query_water_iter = ecs.query_iter(self.ecsu_world.world, self.query_water);
        while (ecs.query_next(&query_water_iter)) {
            const transforms = ecs.field(&query_water_iter, fd.Transform, 0).?;
            const waters = ecs.field(&query_water_iter, fd.Water, 1).?;
            const scales = ecs.field(&query_water_iter, fd.Scale, 2).?;
            for (transforms, waters, scales) |transform, water, scale| {
                if (first_iteration) {
                    first_iteration = false;

                    mesh = self.renderer.getLegacyMesh(water.mesh_handle);
                }

                var instance_data = std.mem.zeroes(InstanceData);
                storeMat44(transform.matrix[0..], &instance_data.object_to_world);

                const z_world = zm.loadMat(instance_data.object_to_world[0..]);
                const z_aabbcenter = zm.loadArr3w(mesh.geometry.*.mAabbCenter, 1.0);
                var bounding_sphere_center: [3]f32 = .{ 0.0, 0.0, 0.0 };
                zm.storeArr3(&bounding_sphere_center, zm.mul(z_aabbcenter, z_world));
                const bounding_sphere_radius = mesh.geometry.*.mRadius * @max(scale.x, @max(scale.y, scale.z));
                if (!camera_comps.camera.isVisible(bounding_sphere_center, bounding_sphere_radius)) {
                    continue;
                }

                storeMat44(transform.inv_matrix[0..], &instance_data.world_to_object);
                // NOTE(gmodarelli): We're using a single material for now
                instance_data.materials_buffer_offset = 0;
                self.instance_data.append(instance_data) catch unreachable;
            }
        }

        if (self.instance_data.items.len > 0) {
            const instance_data_slice = OpaqueSlice{
                .data = @ptrCast(self.instance_data.items),
                .size = self.instance_data.items.len * @sizeOf(InstanceData),
            };
            self.renderer.updateBuffer(instance_data_slice, 0, InstanceData, self.instance_data_buffers[frame_index]);

            self.material_data.clearRetainingCapacity();

            const water_material = WaterMaterial{
                .absorption_color = self.water_material_instance.absorption_color,
                .absorption_coefficient = self.water_material_instance.absorption_coefficient,

                .normal_map_1_texture_index = self.renderer.getTextureBindlessIndex(self.water_material_instance.normal_map_1_texture),
                .normal_map_2_texture_index = self.renderer.getTextureBindlessIndex(self.water_material_instance.normal_map_2_texture),
                .surface_roughness = self.water_material_instance.surface_roughness,
                .surface_opacity = self.water_material_instance.surface_opacity,

                .normal_map_1_params = [4]f32{ self.water_material_instance.normal_map_1_tiling, self.water_material_instance.normal_map_1_direction[0], self.water_material_instance.normal_map_2_direction[1], self.water_material_instance.normal_map_1_intensity },
                .normal_map_2_params = [4]f32{ self.water_material_instance.normal_map_2_tiling, self.water_material_instance.normal_map_2_direction[0], self.water_material_instance.normal_map_2_direction[1], self.water_material_instance.normal_map_2_intensity },
            };
            self.material_data.append(water_material) catch unreachable;

            const material_data_slice = OpaqueSlice{
                .data = @ptrCast(self.material_data.items),
                .size = self.material_data.items.len * @sizeOf(WaterMaterial),
            };
            self.renderer.updateBuffer(material_data_slice, 0, WaterMaterial, self.material_data_buffers[frame_index]);

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
                .instance_material_buffer_index = self.renderer.getBufferBindlessIndex(self.material_data_buffers[frame_index]),
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

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));

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

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));

    var params: [7]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var uniform_frame_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        var uniform_light_buffer = self.renderer.getBuffer(self.uniform_light_buffers[i]);
        var brdf_lut_texture = self.renderer.getTexture(self.renderer.brdf_lut_texture);
        var irradiance_texture = self.renderer.getTexture(self.renderer.irradiance_texture);
        var specular_texture = self.renderer.getTexture(self.renderer.specular_texture);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_frame_buffer);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "cbLight";
        params[1].__union_field3.ppBuffers = @ptrCast(&uniform_light_buffer);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "g_brdf_integration_map";
        params[2].__union_field3.ppTextures = @ptrCast(&brdf_lut_texture);
        params[3] = std.mem.zeroes(graphics.DescriptorData);
        params[3].pName = "g_irradiance_map";
        params[3].__union_field3.ppTextures = @ptrCast(&irradiance_texture);
        params[4] = std.mem.zeroes(graphics.DescriptorData);
        params[4].pName = "g_specular_map";
        params[4].__union_field3.ppTextures = @ptrCast(&specular_texture);
        params[5] = std.mem.zeroes(graphics.DescriptorData);
        params[5].pName = "g_scene_color";
        params[5].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color_copy.*.pTexture);
        params[6] = std.mem.zeroes(graphics.DescriptorData);
        params[6].pName = "g_depth_buffer";
        params[6].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer_copy.*.pTexture);

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

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *WaterRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.water_descriptor_sets);
    graphics.removeDescriptorSet(self.renderer.renderer, self.rt_copy_descriptor_sets);
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
