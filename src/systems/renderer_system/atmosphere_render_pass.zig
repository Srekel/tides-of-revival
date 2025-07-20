const std = @import("std");

const config = @import("../../config/config.zig");
const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const PrefabManager = @import("../../prefab_manager.zig").PrefabManager;
const renderer = @import("../../renderer/renderer.zig");
const util = @import("../../util.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const zm = @import("zmath");
const ztracy = @import("ztracy");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const cubemap_format = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;
const cubemap_width: u32 = 64;
const cubemap_height: u32 = 64;
const threads_count: [2]u32 = .{ 16, 16 };
const dispatch_thread_groups: [3]u32 = .{ cubemap_width / threads_count[0], cubemap_height / threads_count[1], 6 };

const ProceduralSkyParams = struct {
    camera_position: [4]f32,
    sun_direction: [4]f32,
    sun_color_intensity: [4]f32,
    inv_dimensions: [2]f32,
    _pad0: [2]f32,
};

const DrawSkyParams = struct {
    projection: [16]f32,
    view: [16]f32,
    time_of_day_percent: f32,
    _pad0: [3]f32,
};

pub const AtmosphereRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,

    procedural_sky_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    draw_sky_constant_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    skybox_cubemap: renderer.TextureHandle,
    starfield_cubemap: renderer.TextureHandle,

    procedural_sky_descriptor_set: [*c]graphics.DescriptorSet,
    draw_sky_descriptor_set: [*c]graphics.DescriptorSet,

    skybox_mesh: renderer.Mesh,

    pub fn init(self: *AtmosphereRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, prefab_mgr: *PrefabManager, allocator: std.mem.Allocator) void {
        const procedural_sky_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(ProceduralSkyParams);
            }

            break :blk buffers;
        };

        const draw_sky_constant_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(DrawSkyParams);
            }

            break :blk buffers;
        };

        // Load starfield cubemap
        var starfield_cubemap: renderer.TextureHandle = undefined;
        {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.bBindless = false;
            starfield_cubemap = rctx.loadTextureWithDesc(desc, "textures/env/starfield.dds");
        }

        const skybox_cubemap = blk: {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = cubemap_width;
            desc.mHeight = cubemap_height;
            desc.mDepth = 1;
            desc.mArraySize = 6;
            desc.mMipLevels = 1;
            desc.mFormat = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{
                .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE_CUBE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "Skybox Cubemap";

            break :blk rctx.createTexture(desc);
        };

        const skybox_prefab = prefab_mgr.getPrefab(config.prefab.skybox_id).?;
        const skybox_lods = skybox_prefab.get(fd.LodGroup).?;
        const skybox_mesh_handle = skybox_lods.lods[0].mesh_handle;
        const skybox_mesh = rctx.getMesh(skybox_mesh_handle);

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .procedural_sky_constant_buffers = procedural_sky_constant_buffers,
            .draw_sky_constant_buffers = draw_sky_constant_buffers,
            .skybox_cubemap = skybox_cubemap,
            .starfield_cubemap = starfield_cubemap,
            .procedural_sky_descriptor_set = undefined,
            .draw_sky_descriptor_set = undefined,
            .skybox_mesh = skybox_mesh,
        };

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_imgui_fn = null, // renderImGui,
            .render_atmosphere_pass_fn = render,
            .user_data = @ptrCast(self),
        };
        rctx.registerRenderPass(&self.render_pass);
    }

    pub fn destroy(self: *AtmosphereRenderPass) void {
        self.renderer.unregisterRenderPass(&self.render_pass);

        unloadDescriptorSets(@ptrCast(self));
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Atmosphere Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));
    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });

    const skybox_cubemap = self.renderer.getTexture(self.skybox_cubemap);

    // Compute: Procedural Sky
    {
        const camera_pos = camera_comps.transform.getPos00();

        const sun_entity = util.getSun(self.ecsu_world);
        const sun_comps = sun_entity.?.getComps(struct {
            light: *const fd.DirectionalLight,
            rotation: *const fd.Rotation,
        });
        const z_sun_direction = zm.normalize4(zm.rotate(sun_comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 }));
        const sun_light = sun_comps.light.*;

        var procedural_sky_data: ProceduralSkyParams = std.mem.zeroes(ProceduralSkyParams);

        procedural_sky_data.camera_position[0] = camera_pos[0];
        procedural_sky_data.camera_position[1] = camera_pos[1];
        procedural_sky_data.camera_position[2] = camera_pos[2];
        procedural_sky_data.camera_position[3] = 1.0;

        procedural_sky_data.sun_direction[0] = z_sun_direction[0];
        procedural_sky_data.sun_direction[1] = z_sun_direction[1];
        procedural_sky_data.sun_direction[2] = z_sun_direction[2];
        procedural_sky_data.sun_direction[3] = 0.0;

        procedural_sky_data.sun_color_intensity[0] = sun_light.color.r;
        procedural_sky_data.sun_color_intensity[1] = sun_light.color.g;
        procedural_sky_data.sun_color_intensity[2] = sun_light.color.b;
        procedural_sky_data.sun_color_intensity[3] = sun_light.intensity;

        procedural_sky_data.inv_dimensions[0] = 1.0 / @as(f32, @floatFromInt(cubemap_width));
        procedural_sky_data.inv_dimensions[1] = 1.0 / @as(f32, @floatFromInt(cubemap_height));
        procedural_sky_data._pad0 = .{ 42, 42 };

        const data = renderer.Slice{
            .data = @ptrCast(&procedural_sky_data),
            .size = @sizeOf(ProceduralSkyParams),
        };
        self.renderer.updateBuffer(data, ProceduralSkyParams, self.procedural_sky_constant_buffers[frame_index]);

        const input_barrier = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(skybox_cubemap, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, input_barrier.len, @constCast(&input_barrier), 0, null);

        const pipeline_id = IdLocal.init("procedural_sky");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.procedural_sky_descriptor_set);
        graphics.cmdDispatch(cmd_list, dispatch_thread_groups[0], dispatch_thread_groups[1], dispatch_thread_groups[2]);

        const output_barrier = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(skybox_cubemap, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, output_barrier.len, @constCast(&output_barrier), 0, null);
    }

    // Graphics: Draw Sky
    {
        const z_view = zm.loadMat(camera_comps.camera.view[0..]);
        const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
        const t01 = util.getTimeOfDayPercent(self.ecsu_world);

        var draw_sky_data: DrawSkyParams = std.mem.zeroes(DrawSkyParams);
        draw_sky_data.time_of_day_percent = t01;
        zm.storeMat(&draw_sky_data.projection, z_proj);
        zm.storeMat(&draw_sky_data.view, z_view);

        const data = renderer.Slice{
            .data = @ptrCast(&draw_sky_data),
            .size = @sizeOf(DrawSkyParams),
        };
        self.renderer.updateBuffer(data, DrawSkyParams, self.draw_sky_constant_buffers[frame_index]);

        var input_rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_DEPTH_READ),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_rt_barriers.len, @ptrCast(&input_rt_barriers));

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

        const pipeline_id = IdLocal.init("draw_sky");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.draw_sky_descriptor_set);

        const vertex_layout = self.renderer.getVertexLayout(self.skybox_mesh.vertex_layout_id).?;
        const vertex_buffer_count_max = 12; // TODO(gmodarelli): Use MAX_SEMANTICS
        var vertex_buffers: [vertex_buffer_count_max][*c]graphics.Buffer = undefined;

        for (0..vertex_layout.mAttribCount) |attribute_index| {
            const buffer = self.skybox_mesh.geometry.*.__union_field1.__struct_field1.pVertexBuffers[self.skybox_mesh.buffer_layout_desc.mSemanticBindings[@intCast(vertex_layout.mAttribs[attribute_index].mSemantic.bits)]];
            vertex_buffers[attribute_index] = buffer;
        }

        graphics.cmdBindVertexBuffer(cmd_list, vertex_layout.mAttribCount, @constCast(&vertex_buffers), @constCast(&self.skybox_mesh.geometry.*.mVertexStrides), null);
        graphics.cmdBindIndexBuffer(cmd_list, self.skybox_mesh.geometry.*.__union_field1.__struct_field1.pIndexBuffer, self.skybox_mesh.geometry.*.bitfield_1.mIndexType, 0);

        graphics.cmdDrawIndexedInstanced(
            cmd_list,
            self.skybox_mesh.geometry.*.pDrawArgs[0].mIndexCount,
            self.skybox_mesh.geometry.*.pDrawArgs[0].mStartIndex,
            1,
            self.skybox_mesh.geometry.*.pDrawArgs[0].mVertexOffset,
            0,
        );

        var ouptut_rt_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.depth_buffer, graphics.ResourceState.RESOURCE_STATE_DEPTH_READ, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, ouptut_rt_barriers.len, @ptrCast(&ouptut_rt_barriers));
    }
}


fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));

    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;

    var root_signature = self.renderer.getRootSignature(IdLocal.init("procedural_sky"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.procedural_sky_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("draw_sky"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.draw_sky_descriptor_set));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));

    var skybox_cubemap = self.renderer.getTexture(self.skybox_cubemap);
    var starfield_cubemap = self.renderer.getTexture(self.starfield_cubemap);

    for (0..renderer.Renderer.data_buffer_count) |frame_index| {
        {
            var params: [2]graphics.DescriptorData = undefined;
            var procedural_sky_constant_buffer = self.renderer.getBuffer(self.procedural_sky_constant_buffers[frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "FrameBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&procedural_sky_constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "skybox_cubemap";
            params[1].__union_field3.ppTextures = @ptrCast(&skybox_cubemap);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.procedural_sky_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }

        {
            var params: [3]graphics.DescriptorData = undefined;
            var draw_sky_constant_buffer = self.renderer.getBuffer(self.draw_sky_constant_buffers[frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "FrameBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&draw_sky_constant_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "skybox_cubemap";
            params[1].__union_field3.ppTextures = @ptrCast(&skybox_cubemap);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "starfield_cubemap";
            params[2].__union_field3.ppTextures = @ptrCast(&starfield_cubemap);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.draw_sky_descriptor_set, @intCast(params.len), @ptrCast(&params));
        }
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.procedural_sky_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.draw_sky_descriptor_set);
}
