const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const PrecomputedSkyData = struct {
    mip_size: u32 = 0,
    roughness: f32 = 0.0,
};

const UniformFrameData = struct {
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
    directional_lights_buffer_index: u32,
    point_lights_buffer_index: u32,
    directional_lights_count: u32,
    point_lights_count: u32,
};

const PointLight = extern struct {
    position: [3]f32,
    radius: f32,
    color: [3]f32,
    intensity: f32,
};

const DirectionalLight = extern struct {
    direction: [3]f32,
    shadow_map: i32,
    color: [3]f32,
    intensity: f32,
    shadow_range: f32,
    _pad: [2]f32,
    shadow_map_dimensions: i32,
    view_proj: [16]f32,
};

const point_lights_count_max: u32 = 1024;
const directional_lights_count_max: u32 = 8;

const brdf_lut_texture_size: u32 = 512;
const irradiance_texture_size: u32 = 32;
const specular_texture_size: u32 = 128;
const specular_texture_mips: u32 = std.math.log2(specular_texture_size) + 1;

pub const DeferredShadingRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,

    brdf_lut_texture: renderer.TextureHandle,
    irradiance_texture: renderer.TextureHandle,
    specular_texture: renderer.TextureHandle,
    needs_to_compute_ibl_maps: bool,
    brdf_descriptor_set: [*c]graphics.DescriptorSet,
    irradiance_descriptor_set: [*c]graphics.DescriptorSet,
    specular_descriptor_sets: [2][*c]graphics.DescriptorSet,

    directional_lights: std.ArrayList(DirectionalLight),
    point_lights: std.ArrayList(PointLight),
    directional_lights_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    point_lights_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    deferred_descriptor_sets: [2][*c]graphics.DescriptorSet,

    query_directional_lights: ecsu.Query,
    query_point_lights: ecsu.Query,
    query_sky_lights: ecsu.Query,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *DeferredShadingRenderPass {
        const point_lights = std.ArrayList(PointLight).init(allocator);
        const directional_lights = std.ArrayList(DirectionalLight).init(allocator);

        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        var deferred_descriptor_sets: [2][*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("deferred"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&deferred_descriptor_sets[0]));

            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&deferred_descriptor_sets[1]));
        }

        const directional_lights_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = directional_lights_count_max * @sizeOf(DirectionalLight),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Directional Lights Buffer");
            }

            break :blk buffers;
        };

        const point_lights_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const buffer_data = renderer.Slice{
                    .data = null,
                    .size = point_lights_count_max * @sizeOf(PointLight),
                };
                buffers[buffer_index] = rctx.createBindlessBuffer(buffer_data, "Point Lights Buffer");
            }

            break :blk buffers;
        };

        // Create empty texture for BRDF integration map
        const brdf_lut_texture = blk: {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = brdf_lut_texture_size;
            desc.mHeight = brdf_lut_texture_size;
            desc.mDepth = 1;
            desc.mArraySize = 1;
            desc.mMipLevels = 1;
            desc.mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "BRDF LUT";
            break :blk rctx.createTexture(desc);
        };

        // Create empty texture for Irradiance map
        const irradiance_texture = blk: {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = irradiance_texture_size;
            desc.mHeight = irradiance_texture_size;
            desc.mDepth = 1;
            desc.mArraySize = 6;
            desc.mMipLevels = 1;
            desc.mFormat = graphics.TinyImageFormat.R32G32B32A32_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE_CUBE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "Irradiance Map";
            break :blk rctx.createTexture(desc);
        };

        // Create empty texture for Specular map
        const specular_texture = blk: {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = specular_texture_size;
            desc.mHeight = specular_texture_size;
            desc.mDepth = 1;
            desc.mArraySize = 6;
            desc.mMipLevels = specular_texture_mips;
            desc.mFormat = graphics.TinyImageFormat.R32G32B32A32_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE_CUBE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "Specular Map";
            break :blk rctx.createTexture(desc);
        };

        var brdf_descriptor_set: [*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("brdf_integration"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
            desc.mMaxSets = 1;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&brdf_descriptor_set));
        }

        var irradiance_descriptor_set: [*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("compute_irradiance_map"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
            desc.mMaxSets = 1;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&irradiance_descriptor_set));
        }

        var specular_descriptor_sets: [2][*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("compute_specular_map"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
            desc.mMaxSets = 1;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&specular_descriptor_sets[0]));

            const skybox_texture_size: u32 = 1024;
            const max_sets = std.math.log2(skybox_texture_size) + 1;
            desc.mMaxSets = max_sets;
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_DRAW;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&specular_descriptor_sets[1]));
        }

        var query_builder_directional_lights = ecsu.QueryBuilder.init(ecsu_world);
        _ = query_builder_directional_lights
            .withReadonly(fd.Rotation)
            .withReadonly(fd.DirectionalLightComponent);
        const query_directional_lights = query_builder_directional_lights.buildQuery();

        var query_builder_point_lights = ecsu.QueryBuilder.init(ecsu_world);
        _ = query_builder_point_lights
            .withReadonly(fd.Transform)
            .withReadonly(fd.PointLightComponent);
        const query_point_lights = query_builder_point_lights.buildQuery();

        var query_builder_sky_lights = ecsu.QueryBuilder.init(ecsu_world);
        _ = query_builder_sky_lights
            .withReadonly(fd.SkyLightComponent);
        const query_sky_lights = query_builder_sky_lights.buildQuery();

        const pass = allocator.create(DeferredShadingRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .brdf_lut_texture = brdf_lut_texture,
            .irradiance_texture = irradiance_texture,
            .specular_texture = specular_texture,
            .needs_to_compute_ibl_maps = true,
            .brdf_descriptor_set = brdf_descriptor_set,
            .irradiance_descriptor_set = irradiance_descriptor_set,
            .specular_descriptor_sets = specular_descriptor_sets,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
            .deferred_descriptor_sets = deferred_descriptor_sets,
            .directional_lights = directional_lights,
            .point_lights = point_lights,
            .directional_lights_buffers = directional_lights_buffers,
            .point_lights_buffers = point_lights_buffers,
            .query_directional_lights = query_directional_lights,
            .query_point_lights = query_point_lights,
            .query_sky_lights = query_sky_lights,
        };

        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *DeferredShadingRenderPass) void {
        self.query_directional_lights.deinit();
        self.query_point_lights.deinit();
        self.query_sky_lights.deinit();
        self.point_lights.deinit();
        self.directional_lights.deinit();
        self.allocator.destroy(self);
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

pub const renderFn: renderer.renderPassRenderFn = render;
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Deferred Shading Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *DeferredShadingRenderPass = @ptrCast(@alignCast(user_data));

    const frame_index = self.renderer.frame_index;

    var entity_iter_sky_lights = self.query_sky_lights.iterator(struct {
        sky_light: *const fd.SkyLightComponent,
    });

    // NOTE(gmodarelli): I'm assuming only 1 skylight for the moment
    if (entity_iter_sky_lights.next()) |comps| {
        if (self.needs_to_compute_ibl_maps) {
            const new_trazy_zone = ztracy.ZoneNC(@src(), "Compute IBL Maps", 0x00_ff_ff_00);
            defer new_trazy_zone.End();

            var hdir_texture = self.renderer.getTexture(comps.sky_light.hdri);
            var brdf_lut_texture = self.renderer.getTexture(self.brdf_lut_texture);
            var irradiance_texture = self.renderer.getTexture(self.irradiance_texture);
            var specular_texture = self.renderer.getTexture(self.specular_texture);

            // Compute the BRDF Integration Map
            {
                const input_barrier = [_]graphics.TextureBarrier{
                    graphics.TextureBarrier.init(brdf_lut_texture, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, input_barrier.len, @constCast(&input_barrier), 0, null);

                const pipeline = self.renderer.getPSO(IdLocal.init("brdf_integration"));
                graphics.cmdBindPipeline(cmd_list, pipeline);
                var params: [1]graphics.DescriptorData = undefined;
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "dstTexture";
                params[0].__union_field3.ppTextures = @ptrCast(&brdf_lut_texture);
                graphics.updateDescriptorSet(self.renderer.renderer, 0, self.brdf_descriptor_set, @intCast(params.len), @ptrCast(&params));
                graphics.cmdBindDescriptorSet(cmd_list, 0, self.brdf_descriptor_set);
                // TODO(gmodarelli): Read shader reflections to get the thread group size. We need bindings for IShaderReflection.h
                const thread_group_size = [3]u32{ 16, 16, 1 };
                graphics.cmdDispatch(cmd_list, brdf_lut_texture_size / thread_group_size[0], brdf_lut_texture_size / thread_group_size[1], thread_group_size[2]);

                const output_barrier = [_]graphics.TextureBarrier{
                    graphics.TextureBarrier.init(brdf_lut_texture, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, output_barrier.len, @constCast(&output_barrier), 0, null);
            }

            // Compute Sky Irradiance
            {
                const input_barrier = [_]graphics.TextureBarrier{
                    graphics.TextureBarrier.init(irradiance_texture, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, input_barrier.len, @constCast(&input_barrier), 0, null);

                const pipeline = self.renderer.getPSO(IdLocal.init("compute_irradiance_map"));
                graphics.cmdBindPipeline(cmd_list, pipeline);
                var params: [2]graphics.DescriptorData = undefined;
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "srcTexture";
                params[0].__union_field3.ppTextures = @ptrCast(&hdir_texture);
                params[1] = std.mem.zeroes(graphics.DescriptorData);
                params[1].pName = "dstTexture";
                params[1].__union_field3.ppTextures = @ptrCast(&irradiance_texture);
                graphics.updateDescriptorSet(self.renderer.renderer, 0, self.irradiance_descriptor_set, @intCast(params.len), @ptrCast(&params));
                graphics.cmdBindDescriptorSet(cmd_list, 0, self.irradiance_descriptor_set);
                // TODO(gmodarelli): Read shader reflections to get the thread group size. We need bindings for IShaderReflection.h
                const thread_group_size = [3]u32{ 16, 16, 1 };
                graphics.cmdDispatch(cmd_list, irradiance_texture_size / thread_group_size[0], irradiance_texture_size / thread_group_size[1], 6);

                const output_barrier = [_]graphics.TextureBarrier{
                    graphics.TextureBarrier.init(irradiance_texture, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, output_barrier.len, @constCast(&output_barrier), 0, null);
            }

            // Compute Sky Specular
            {
                const input_barrier = [_]graphics.TextureBarrier{
                    graphics.TextureBarrier.init(specular_texture, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, input_barrier.len, @constCast(&input_barrier), 0, null);

                const pipeline_id = IdLocal.init("compute_specular_map");
                const pipeline = self.renderer.getPSO(pipeline_id);
                const root_signature = self.renderer.getRootSignature(pipeline_id);
                graphics.cmdBindPipeline(cmd_list, pipeline);
                var params: [1]graphics.DescriptorData = undefined;
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "srcTexture";
                params[0].__union_field3.ppTextures = @ptrCast(&hdir_texture);
                graphics.updateDescriptorSet(self.renderer.renderer, 0, self.specular_descriptor_sets[0], @intCast(params.len), @ptrCast(&params));
                graphics.cmdBindDescriptorSet(cmd_list, 0, self.specular_descriptor_sets[0]);

                const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
                std.debug.assert(root_constant_index != std.math.maxInt(u32));

                for (0..specular_texture_mips) |i| {
                    const push_constants = PrecomputedSkyData{
                        .mip_size = specular_texture_size >> @intCast(i),
                        .roughness = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(specular_texture_mips - 1)),
                    };
                    graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));

                    params[0] = std.mem.zeroes(graphics.DescriptorData);
                    params[0].pName = "dstTexture";
                    params[0].__union_field3.ppTextures = @ptrCast(&specular_texture);
                    params[0].__union_field1.__struct_field1.mUAVMipSlice = @intCast(i);
                    params[0].__union_field1.__struct_field1.mBindMipChain = false;
                    graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.specular_descriptor_sets[1], @intCast(params.len), @ptrCast(&params));
                    graphics.cmdBindDescriptorSet(cmd_list, @intCast(i), self.specular_descriptor_sets[1]);

                    // TODO(gmodarelli): Read shader reflections to get the thread group size. We need bindings for IShaderReflection.h
                    const thread_group_size = [3]u32{ 16, 16, 6 };
                    graphics.cmdDispatch(cmd_list, @max(1, (specular_texture_size >> @intCast(i)) / thread_group_size[0]), @max(1, (specular_texture_size >> @intCast(i)) / thread_group_size[1]), 6);
                }

                const output_barrier = [_]graphics.TextureBarrier{
                    graphics.TextureBarrier.init(specular_texture, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, output_barrier.len, @constCast(&output_barrier), 0, null);
            }

            prepareDescriptorSets(@ptrCast(self));
            self.needs_to_compute_ibl_maps = false;
        }
    }

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
    self.uniform_frame_data.directional_lights_buffer_index = self.renderer.getBufferBindlessIndex(self.directional_lights_buffers[frame_index]);
    self.uniform_frame_data.directional_lights_count = @intCast(self.directional_lights.items.len);
    self.uniform_frame_data.point_lights_buffer_index = self.renderer.getBufferBindlessIndex(self.point_lights_buffers[frame_index]);
    self.uniform_frame_data.point_lights_count = @intCast(self.point_lights.items.len);

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data),
        .size = @sizeOf(UniformFrameData),
    };
    self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);

    var entity_iter_directional_lights = self.query_directional_lights.iterator(struct {
        rotation: *const fd.Rotation,
        light: *const fd.DirectionalLightComponent,
    });

    self.directional_lights.clearRetainingCapacity();

    while (entity_iter_directional_lights.next()) |comps| {
        const z_forward = zm.rotate(comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 });
        // TODO(gmodarelli): Specify data for shadow mapping
        const directional_light = DirectionalLight{
            .direction = [3]f32{ -z_forward[0], -z_forward[1], -z_forward[2] },
            .shadow_map = 0,
            .color = [3]f32{ comps.light.color.r, comps.light.color.g, comps.light.color.b },
            .intensity = comps.light.intensity,
            .shadow_range = 0.0,
            ._pad = [2]f32{ 42, 42 },
            .shadow_map_dimensions = 0,
            .view_proj = [16]f32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        };
        self.directional_lights.append(directional_light) catch unreachable;
    }

    var entity_iter_point_lights = self.query_point_lights.iterator(struct {
        transform: *const fd.Transform,
        light: *const fd.PointLightComponent,
    });

    self.point_lights.clearRetainingCapacity();

    while (entity_iter_point_lights.next()) |comps| {
        const point_light = PointLight{
            .position = comps.transform.getPos00(),
            .radius = comps.light.range,
            .color = [3]f32{ comps.light.color.r, comps.light.color.g, comps.light.color.b },
            .intensity = comps.light.intensity,
        };

        self.point_lights.append(point_light) catch unreachable;
    }

    if (self.directional_lights.items.len > 0) {
        const directional_lights_slice = renderer.Slice{
            .data = @ptrCast(self.directional_lights.items),
            .size = self.directional_lights.items.len * @sizeOf(DirectionalLight),
        };
        self.renderer.updateBuffer(directional_lights_slice, DirectionalLight, self.directional_lights_buffers[frame_index]);
    }

    if (self.point_lights.items.len > 0) {
        const point_lights_slice = renderer.Slice{
            .data = @ptrCast(self.point_lights.items),
            .size = self.point_lights.items.len * @sizeOf(PointLight),
        };
        self.renderer.updateBuffer(point_lights_slice, PointLight, self.point_lights_buffers[frame_index]);
    }

    // Deferred Shading commands
    {
        const pipeline_id = IdLocal.init("deferred");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.deferred_descriptor_sets[0]);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.deferred_descriptor_sets[1]);
        graphics.cmdDraw(cmd_list, 3, 0);
    }
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *DeferredShadingRenderPass = @ptrCast(@alignCast(user_data));

    var params: [7]graphics.DescriptorData = undefined;

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var brdf_lut_texture = self.renderer.getTexture(self.brdf_lut_texture);
        var irradiance_texture = self.renderer.getTexture(self.irradiance_texture);
        var specular_texture = self.renderer.getTexture(self.specular_texture);

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "brdfIntegrationMap";
        params[0].__union_field3.ppTextures = @ptrCast(&brdf_lut_texture);
        params[1] = std.mem.zeroes(graphics.DescriptorData);
        params[1].pName = "irradianceMap";
        params[1].__union_field3.ppTextures = @ptrCast(&irradiance_texture);
        params[2] = std.mem.zeroes(graphics.DescriptorData);
        params[2].pName = "specularMap";
        params[2].__union_field3.ppTextures = @ptrCast(&specular_texture);
        params[3] = std.mem.zeroes(graphics.DescriptorData);
        params[3].pName = "gBuffer0";
        params[3].__union_field3.ppTextures = @ptrCast(&self.renderer.gbuffer_0.*.pTexture);
        params[4] = std.mem.zeroes(graphics.DescriptorData);
        params[4].pName = "gBuffer1";
        params[4].__union_field3.ppTextures = @ptrCast(&self.renderer.gbuffer_1.*.pTexture);
        params[5] = std.mem.zeroes(graphics.DescriptorData);
        params[5].pName = "gBuffer2";
        params[5].__union_field3.ppTextures = @ptrCast(&self.renderer.gbuffer_2.*.pTexture);
        params[6] = std.mem.zeroes(graphics.DescriptorData);
        params[6].pName = "depthBuffer";
        params[6].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer.*.pTexture);
        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.deferred_descriptor_sets[0], 7, @ptrCast(&params));

        var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "cbFrame";
        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

        graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.deferred_descriptor_sets[1], 1, @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *DeferredShadingRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.deferred_descriptor_sets[0]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.deferred_descriptor_sets[1]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.specular_descriptor_sets[0]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.specular_descriptor_sets[1]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.irradiance_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.brdf_descriptor_set);
}
