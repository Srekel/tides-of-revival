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

pub const transmittance_lut_format = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;
pub const camera_scattering_volume_format = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;

// Look Up Tables Info
const transmittance_texture_width: u32 = 256;
const transmittance_texture_height: u32 = 64;
const scattering_texture_r_size: u32 = 32;
const scattering_texture_mu_size: u32 = 128;
const scattering_texture_mu_s_size: u32 = 32;
const scattering_texture_nu_size: u32 = 8;
const irradiance_texture_width: u32 = 64;
const irradiance_texture_height: u32 = 16;
const scattering_texture_width: u32 = scattering_texture_nu_size * scattering_texture_mu_s_size;
const scattering_texture_height: u32 = scattering_texture_mu_size;
const scattering_texture_depth: u32 = scattering_texture_r_size;

const multi_scattering_texture_resolution: u32 = 32;

const illuminance_is_one: bool = true;

const FrameBuffer = struct {
	view_proj_mat: [16]f32,
	color: [4]f32,

	sun_illuminance: [3]f32,
	scattering_max_path_depth: i32,

	resolution: [2]u32,
	frame_time_sec: f32,
	time_sec: f32,

	ray_march_min_max_spp: [2]f32,
	pad: [2]f32,
};

const SkyAtmosphereBuffer = struct
{
	//
	// From AtmosphereParameters
	//

	solar_irradiance: [3]f32,
	sun_angular_radius: f32,

	absorption_extinction: [3]f32,
	mu_s_min: f32,

	rayleigh_scattering: [3]f32,
	mie_phase_function_g: f32,

	mie_scattering: [3]f32,
	bottom_radius: f32,

	mie_extinction: [3]f32,
	top_radius: f32,

	mie_absorption: [3]f32,
	pad00: f32,

	ground_albedo: [3]f32,
	pad0: f32,

	rayleigh_density: [12]f32,
	mie_density: [12]f32,
	absorption_density: [12]f32,

	//
	// Add generated static header constant
	//

	transmittance_texture_width: i32,
	transmittance_texture_height: i32,
	irradiance_texture_width: i32,
	irradiance_texture_height: i32,

	scattering_texture_r_size: i32,
	scattering_texture_mu_size: i32,
	scattering_texture_mu_s_size: i32,
	scattering_texture_nu_size: i32,

	sky_spectral_radiance_to_luminance: [3]f32,
	pad3: f32,
	sun_spectral_radiance_to_luminance: [3]f32,
	pad4: f32,

	//
	// Other globals
	//
	sky_view_proj_mat: [16]f32,
	sky_inv_view_proj_mat: [16]f32,
	sky_inv_proj_mat: [16]f32,
	sky_inv_view_mat: [16]f32,
	shadowmap_view_proj_mat: [16]f32,

	camera: [3]f32,
	pad5: f32,
	sun_direction: [3]f32,
	pad6: f32,
	view_ray: [3]f32,
	pad7: f32,

	multiple_scattering_factor: f32,
	multi_scattering_LUT_res: f32,
	pad9: f32,
	pad10: f32,
};

pub const AtmosphereRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,

    frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    sky_atmosphere_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    transmittance_lut: [*c]graphics.RenderTarget,
    multi_scattering_texture: renderer.TextureHandle,
    camera_scattering_volume_rt: [*c]graphics.RenderTarget,

    transmittance_lut_descriptor_set: [*c]graphics.DescriptorSet,
    multi_scattering_descriptor_set: [*c]graphics.DescriptorSet,
    camera_scattering_volume_descriptor_set: [*c]graphics.DescriptorSet,
    sky_ray_marching_descriptor_set: [*c]graphics.DescriptorSet,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *AtmosphereRenderPass {
        const frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(FrameBuffer);
            }

            break :blk buffers;
        };

        const sky_atmosphere_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(SkyAtmosphereBuffer);
            }

            break :blk buffers;
        };

        const transmittance_lut = blk: {
            var rt: [*c]graphics.RenderTarget = null;
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Transmittance LUT";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = transmittance_lut_format;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = transmittance_texture_width;
            rt_desc.mHeight = transmittance_texture_height;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(rctx.renderer, &rt_desc, &rt);

            break :blk rt;
        };

        const multi_scattering_texture = blk: {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = multi_scattering_texture_resolution;
            desc.mHeight = multi_scattering_texture_resolution;
            desc.mDepth = 1;
            desc.mArraySize = 1;
            desc.mMipLevels = 1;
            desc.mFormat = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "Multi Scattering";

            break :blk rctx.createTexture(desc);
        };

        const camera_scattering_volume_rt = blk: {
            var rt: [*c]graphics.RenderTarget = null;
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Camera Scattering Volume";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mFormat = camera_scattering_volume_format;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = 32;
            rt_desc.mHeight = 32;
            rt_desc.mDepth = 32;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(rctx.renderer, &rt_desc, &rt);

            break :blk rt;
        };

        const pass = allocator.create(AtmosphereRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .transmittance_lut = transmittance_lut,
            .multi_scattering_texture = multi_scattering_texture,
            .camera_scattering_volume_rt = camera_scattering_volume_rt,
            .frame_buffers = frame_buffers,
            .sky_atmosphere_buffers = sky_atmosphere_buffers,
            .transmittance_lut_descriptor_set = undefined,
            .multi_scattering_descriptor_set = undefined,
            .camera_scattering_volume_descriptor_set = undefined,
            .sky_ray_marching_descriptor_set = undefined,
        };

        createDescriptorSets(@ptrCast(pass));
        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *AtmosphereRenderPass) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.transmittance_lut_descriptor_set);

        // NOTE(gmodarelli): We can remove the render target here because we can't wait
        // for the gpu to be idle
        // TODO(gmodarelli): Move RT creation/deletion to renderer.zig
        // graphics.removeRenderTarget(self.renderer.renderer, self.transmittance_lut);

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
pub const createDescriptorSetsFn: renderer.renderPassCreateDescriptorSetsFn = createDescriptorSets;
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

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

    // Convert camera_pos and z_view (translation) to km
    var camera_pos = camera_comps.transform.getPos00();
    camera_pos[0] /= 1000.0;
    camera_pos[1] /= 1000.0;
    camera_pos[2] /= 1000.0;

    var z_view = zm.loadMat(camera_comps.camera.view[0..]);
    z_view[3][0] /= 1000.0;
    z_view[3][1] /= 1000.0;
    z_view[3][2] /= 1000.0;

    const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
    const z_proj_view = zm.mul(z_view, z_proj);
    const z_cam_direction = zm.util.getAxisZ(zm.loadMat43(&camera_comps.transform.matrix));

    const sun_entity = util.getSun(self.ecsu_world);
    const sun_comps = sun_entity.?.getComps(struct {
        rotation: *const fd.Rotation,
    });
    const z_sun_direction = zm.normalize4(zm.rotate(sun_comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 }));

    // Update Frame buffer
    var frame_buffer_data: FrameBuffer = blk: {
        var frame_buffer_data: FrameBuffer = std.mem.zeroes(FrameBuffer);

        zm.storeMat(&frame_buffer_data.view_proj_mat, z_proj_view);
        frame_buffer_data.color = [4]f32{0.0, 1.0, 1.0, 1.0};
        frame_buffer_data.resolution = [2]u32{@intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1])};
        frame_buffer_data.sun_illuminance = [3]f32{ 1.0, 1.0, 1.0 };
        frame_buffer_data.scattering_max_path_depth = 4;
        frame_buffer_data.frame_time_sec = 0.0; // unused so far
        frame_buffer_data.time_sec = 0.0; // unused so far
        frame_buffer_data.ray_march_min_max_spp = [2]f32{4.0, 14.0};

        const data = renderer.Slice{
            .data = @ptrCast(&frame_buffer_data),
            .size = @sizeOf(FrameBuffer),
        };
        self.renderer.updateBuffer(data, FrameBuffer, self.frame_buffers[frame_index]);

        break :blk frame_buffer_data;
    };

    // Update Sky Atmosphere Buffer
    {
        var sky_atmosphere_buffer = std.mem.zeroes(SkyAtmosphereBuffer);
        setupEarthAtmosphere(&sky_atmosphere_buffer);
        sky_atmosphere_buffer.transmittance_texture_width = transmittance_texture_width;
        sky_atmosphere_buffer.transmittance_texture_height = transmittance_texture_height;
        sky_atmosphere_buffer.irradiance_texture_width = irradiance_texture_width;
        sky_atmosphere_buffer.irradiance_texture_height = irradiance_texture_height;
        sky_atmosphere_buffer.scattering_texture_r_size = scattering_texture_r_size;
        sky_atmosphere_buffer.scattering_texture_mu_size = scattering_texture_mu_size;
        sky_atmosphere_buffer.scattering_texture_mu_s_size = scattering_texture_mu_s_size;
        sky_atmosphere_buffer.scattering_texture_nu_size = scattering_texture_nu_size;
        sky_atmosphere_buffer.sky_spectral_radiance_to_luminance = [3]f32{114974.916437, 71305.954816, 65310.548555};
        sky_atmosphere_buffer.sun_spectral_radiance_to_luminance = [3]f32{98242.786222, 69954.398112, 66475.012354};
        zm.storeMat(&sky_atmosphere_buffer.sky_view_proj_mat, z_proj_view);
        zm.storeMat(&sky_atmosphere_buffer.sky_inv_view_proj_mat, zm.inverse(z_proj_view));
        zm.storeMat(&sky_atmosphere_buffer.sky_inv_view_mat, zm.inverse(z_view));
        zm.storeMat(&sky_atmosphere_buffer.sky_inv_proj_mat, zm.inverse(z_proj));
        @memcpy(&sky_atmosphere_buffer.camera, &camera_pos);
        zm.storeArr3(&sky_atmosphere_buffer.view_ray, z_cam_direction);
        zm.storeArr3(&sky_atmosphere_buffer.sun_direction, -z_sun_direction);
        // TODO(gmodarelli): Set `sky_atmosphere_buffer.shadowmap_view_proj_mat`
        sky_atmosphere_buffer.multiple_scattering_factor = 1.0; // TODO(gmodarelli): Expose a 0-1 slider
        sky_atmosphere_buffer.multi_scattering_LUT_res = multi_scattering_texture_resolution;
        const data = renderer.Slice{
            .data = @ptrCast(&sky_atmosphere_buffer),
            .size = @sizeOf(SkyAtmosphereBuffer),
        };
        self.renderer.updateBuffer(data, SkyAtmosphereBuffer, self.sky_atmosphere_buffers[frame_index]);
    }

    // Render Transmittance LUT
    {
        var input_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.transmittance_lut, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

        // Update descriptors
        {
            var params: [1]graphics.DescriptorData = undefined;
            var sky_atmosphere_buffer = self.renderer.getBuffer(self.sky_atmosphere_buffers[frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "SkyAtmosphereBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&sky_atmosphere_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.transmittance_lut_descriptor_set, 1, @ptrCast(&params));
        }

        var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
        bind_render_targets_desc.mRenderTargetCount = 1;
        bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.transmittance_lut;
        bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

        graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

        graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(transmittance_texture_width), @floatFromInt(transmittance_texture_height), 0.0, 1.0);
        graphics.cmdSetScissor(cmd_list, 0, 0, transmittance_texture_width, transmittance_texture_height);

        const pipeline_id = IdLocal.init("transmittance_lut");
        const pipeline = self.renderer.getPSO(pipeline_id);

        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.transmittance_lut_descriptor_set);
        graphics.cmdDraw(cmd_list, 3, 0);

        var output_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.transmittance_lut, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));
    }

    // Render Multi Scattering
    {
        var multi_scattering_texture = self.renderer.getTexture(self.multi_scattering_texture);

        const input_barrier = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(multi_scattering_texture, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, input_barrier.len, @constCast(&input_barrier), 0, null);

        // Update descriptors
        {
            var params: [4]graphics.DescriptorData = undefined;
            var params_count: u32 = 3;

            var frame_buffer = self.renderer.getBuffer(self.frame_buffers[frame_index]);
            var sky_atmosphere_buffer = self.renderer.getBuffer(self.sky_atmosphere_buffers[frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "SkyAtmosphereBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&sky_atmosphere_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "transmittance_lut_texture";
            params[1].__union_field3.ppTextures = @ptrCast(&self.transmittance_lut.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "output_texture";
            params[2].__union_field3.ppTextures = @ptrCast(&multi_scattering_texture);

            if (!illuminance_is_one) {
                params[3] = std.mem.zeroes(graphics.DescriptorData);
                params[3].pName = "FrameBuffer";
                params[3].__union_field3.ppBuffers = @ptrCast(&frame_buffer);

                params_count += 1;
            }

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.multi_scattering_descriptor_set, params_count, @ptrCast(&params));
        }

        const pipeline_id = IdLocal.init("multi_scattering");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.multi_scattering_descriptor_set);
        graphics.cmdDispatch(cmd_list, multi_scattering_texture_resolution, multi_scattering_texture_resolution, 1);

        const output_barrier = [_]graphics.TextureBarrier{
            graphics.TextureBarrier.init(multi_scattering_texture, graphics.ResourceState.RESOURCE_STATE_UNORDERED_ACCESS, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, output_barrier.len, @constCast(&output_barrier), 0, null);
    }

    // NOTE(gmodarelli): This pass is only needed when rendering with Fast Aerial Perspective enabled
    // Camera Volume
    if (false) {
        // Update Frame buffer
        {
            frame_buffer_data.resolution = [2]u32{ 32, 32 };

            const data = renderer.Slice{
                .data = @ptrCast(&frame_buffer_data),
                .size = @sizeOf(FrameBuffer),
            };
            self.renderer.updateBuffer(data, FrameBuffer, self.frame_buffers[frame_index]);
        }

        var input_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.camera_scattering_volume_rt, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

        // Update descriptors
        {
            var multi_scattering_texture = self.renderer.getTexture(self.multi_scattering_texture);
            var params: [4]graphics.DescriptorData = undefined;

            var frame_buffer = self.renderer.getBuffer(self.frame_buffers[frame_index]);
            var sky_atmosphere_buffer = self.renderer.getBuffer(self.sky_atmosphere_buffers[frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "FrameBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "SkyAtmosphereBuffer";
            params[1].__union_field3.ppBuffers = @ptrCast(&sky_atmosphere_buffer);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "transmittance_lut_texture";
            params[2].__union_field3.ppTextures = @ptrCast(&self.transmittance_lut.*.pTexture);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "multi_scat_texture";
            params[3].__union_field3.ppTextures = @ptrCast(&multi_scattering_texture);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.camera_scattering_volume_descriptor_set, 4, @ptrCast(&params));
        }

        var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
        bind_render_targets_desc.mRenderTargetCount = 1;
        bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.camera_scattering_volume_rt;
        bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

        graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

        graphics.cmdSetViewport(cmd_list, 0.0, 0.0, 32.0, 32.0, 0.0, 1.0);
        graphics.cmdSetScissor(cmd_list, 0, 0, 32, 32);

        const pipeline_id = IdLocal.init("camera_volume");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.camera_scattering_volume_descriptor_set);
        graphics.cmdDrawInstanced(cmd_list, 3, 0, 32, 0);

        var output_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.camera_scattering_volume_rt, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
        };
        graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));
    }

    // Sky Ray Marching
    {
        // Update Frame buffer
        {
            frame_buffer_data.resolution = [2]u32{ @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]) };

            const data = renderer.Slice{
                .data = @ptrCast(&frame_buffer_data),
                .size = @sizeOf(FrameBuffer),
            };
            self.renderer.updateBuffer(data, FrameBuffer, self.frame_buffers[frame_index]);
        }

        // NOTE(gmodarelli): Scene Color and Depth Buffer are already in the right state, no need for barriers

        // Update descriptors
        {
            var params: [5]graphics.DescriptorData = undefined;

            var frame_buffer = self.renderer.getBuffer(self.frame_buffers[frame_index]);
            var sky_atmosphere_buffer = self.renderer.getBuffer(self.sky_atmosphere_buffers[frame_index]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "FrameBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "SkyAtmosphereBuffer";
            params[1].__union_field3.ppBuffers = @ptrCast(&sky_atmosphere_buffer);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "view_depth_texture";
            params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer.*.pTexture);
            if (true) {
                var multi_scattering_texture = self.renderer.getTexture(self.multi_scattering_texture);

                params[3] = std.mem.zeroes(graphics.DescriptorData);
                params[3].pName = "transmittance_lut_texture";
                params[3].__union_field3.ppTextures = @ptrCast(&self.transmittance_lut.*.pTexture);
                params[4] = std.mem.zeroes(graphics.DescriptorData);
                params[4].pName = "multi_scat_texture";
                params[4].__union_field3.ppTextures = @ptrCast(&multi_scattering_texture);
            } else {
                params[3] = std.mem.zeroes(graphics.DescriptorData);
                params[3].pName = "atmosphere_camera_scattering_volume";
                params[3].__union_field3.ppTextures = @ptrCast(&self.camera_scattering_volume_rt.*.pTexture);
            }

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.sky_ray_marching_descriptor_set, 4, @ptrCast(&params));
        }

        var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
        bind_render_targets_desc.mRenderTargetCount = 1;
        bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.renderer.scene_color;
        bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;

        graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

        graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.renderer.window.frame_buffer_size[0]), @floatFromInt(self.renderer.window.frame_buffer_size[1]), 0.0, 1.0);
        graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]));

        const pipeline_id = IdLocal.init("sky_ray_marching");
        const pipeline = self.renderer.getPSO(pipeline_id);
        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.sky_ray_marching_descriptor_set);
        graphics.cmdDraw(cmd_list, 3, 0);
    }

    graphics.cmdBindRenderTargets(cmd_list, null);
}

fn setupEarthAtmosphere(sky_atmosphere: *SkyAtmosphereBuffer) void {
	// Values shown here are the result of integration over wavelength power spectrum integrated with paricular function.
	// Refer to https://github.com/ebruneton/precomputed_atmospheric_scattering for details.

	// All units in kilometers
	const earth_bottom_radius: f32 = 6360.0;
	const earth_top_radius: f32 = 6460.0;   // 100km atmosphere radius, less edge visible and it contain 99.99% of the atmosphere medium https://en.wikipedia.org/wiki/K%C3%A1rm%C3%A1n_line
	const earth_rayleigh_scale_height: f32 = 8.0;
	const earth_mie_scale_height: f32 = 1.2;

	// Sun - This should not be part of the sky model...
	//sky_atmosphere.solar_irradiance = { 1.474000f, 1.850400f, 1.911980f };
	sky_atmosphere.solar_irradiance = [3]f32{ 1.0, 1.0, 1.0 };	// Using a normalise sun illuminance. This is to make sure the LUTs acts as a transfert factor to apply the runtime computed sun irradiance over.
	sky_atmosphere.sun_angular_radius = 0.004675;

	// Earth
	sky_atmosphere.bottom_radius = earth_bottom_radius;
	sky_atmosphere.top_radius = earth_top_radius;
	sky_atmosphere.ground_albedo = [3]f32{ 0.0, 0.0, 0.0 };

    // TODO(gmodarelli): These are probably Z-up. Change them to Y-up
    // Or maybe it's just a coincidence, so change rayleigh_density from
    // a [12]f32 to a proper struct with fields
	// Raleigh scattering
	// sky_atmosphere.rayleigh_density[0] = [4]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
	// sky_atmosphere.rayleigh_density[1] = [4]f32{ 0.0, 1.0, -1.0 / earth_rayleigh_scale_height, 0.0, 0.0 };
    sky_atmosphere.rayleigh_density = [12]f32{
        0.0, 0.0, 0.0, 0.0, 0.0,                                    // Layer 1
        0.0, 1.0, -1.0 / earth_rayleigh_scale_height, 0.0, 0.0,     // Layer 2
        42.0, 42.0,                                                 // Padding
    };
	sky_atmosphere.rayleigh_scattering = [3]f32{ 0.005802, 0.013558, 0.033100 };		// 1/km

	// Mie scattering
	// sky_atmosphere.mie_density[0] = [4]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 };
	// sky_atmosphere.mie_density[1] = [4]f32{ 0.0, 1.0, -1.0 / earth_mie_scale_height, 0.0, 0.0 };
    sky_atmosphere.mie_density = [12]f32{
        0.0, 0.0, 0.0, 0.0, 0.0,                            // Layer 1
        0.0, 1.0, -1.0 / earth_mie_scale_height, 0.0, 0.0,  // Layer 2
        42.0, 42.0,                                         // Padding
    };
	sky_atmosphere.mie_scattering = [3]f32{ 0.003996, 0.003996, 0.003996 };			// 1/km
	sky_atmosphere.mie_extinction = [3]f32{ 0.004440, 0.004440, 0.004440 };			// 1/km
    sky_atmosphere.mie_absorption = [3]f32{
        @max(0.0, sky_atmosphere.mie_extinction[0] - sky_atmosphere.mie_scattering[0]),
        @max(0.0, sky_atmosphere.mie_extinction[1] - sky_atmosphere.mie_scattering[1]),
        @max(0.0, sky_atmosphere.mie_extinction[2] - sky_atmosphere.mie_scattering[2]),
    };
	sky_atmosphere.mie_phase_function_g = 0.8;

	// Ozone absorption
	// sky_atmosphere.absorption_density[0] = [4]f32{ 25.0, 0.0, 0.0, 1.0 / 15.0, -2.0 / 3.0 };
	// sky_atmosphere.absorption_density[1] = [4]f32{ 0.0, 0.0, 0.0, -1.0 / 15.0, 8.0 / 3.0 };
    sky_atmosphere.absorption_density = [12]f32{
        25.0, 0.0, 0.0, 1.0 / 15.0, -2.0 / 3.0, // Layer 1
        0.0, 0.0, 0.0, -1.0 / 15.0, 8.0 / 3.0,  // Layer 2
        42.0, 42.0,                             // Padding
    };
	sky_atmosphere.absorption_extinction = [3]f32{ 0.000650, 0.001881, 0.000085 };	// 1/km

	const max_sun_zenith_angle: f32 = std.math.pi * 120.0 / 180.0; // (use_half_precision_ ? 102.0 : 120.0) / 180.0 * kPi;
	sky_atmosphere.mu_s_min = std.math.cos(max_sun_zenith_angle);

}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));

    var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
    desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
    desc.mMaxSets = renderer.Renderer.data_buffer_count;

    var root_signature = self.renderer.getRootSignature(IdLocal.init("transmittance_lut"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.transmittance_lut_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("multi_scattering"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.multi_scattering_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("camera_volume"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.camera_scattering_volume_descriptor_set));

    root_signature = self.renderer.getRootSignature(IdLocal.init("sky_ray_marching"));
    desc.pRootSignature = root_signature;
    graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&self.sky_ray_marching_descriptor_set));
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    _ = user_data;
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.transmittance_lut_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.multi_scattering_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.camera_scattering_volume_descriptor_set);
    graphics.removeDescriptorSet(self.renderer.renderer, self.sky_ray_marching_descriptor_set);
}
