const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const zforge = @import("zforge");
const zgui = @import("zgui");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const transmittance_lut_format = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;
pub const camera_scattering_volume_format = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;

// Look Up Tables Info
pub const transmittance_texture_width: u32 = 256;
pub const transmittance_texture_height: u32 = 64;
pub const camera_scattering_volume_resolution = 32;
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

const SkyAtmosphereConstantBuffer = struct {
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

// An atmosphere layer of width 'width', and whose density is defined as
//   'exp_term' * exp('exp_scale' * h) + 'linear_term' * h + 'constant_term',
// clamped to [0,1], and where h is the altitude.
const DensityProfileLayer = extern struct {
    width: f32,
    exp_term: f32,
    exp_scale: f32,
    linear_term: f32,
    constant_term: f32,
};

// An atmosphere density profile made of several layers on top of each other
// (from bottom to top). The width of the last layer is ignored, i.e. it always
// extend to the top atmosphere boundary. The profile values vary between 0
// (null density) to 1 (maximum density).
const DensityProfile = extern struct {
    layers: [2]DensityProfileLayer,
};

const AtmoshereInfo = extern struct {
    // The solar irradiance at the top of the atmosphere
    solar_irradiance: [3]f32,
    // The sun angular radius. Warning: the implementation uses approximations
    // that are valid only if this angle is smaller than 0.1 radians
    sun_angular_radius: f32,
    // The distance between the planet center and the bottom of the atmosphere
    bottom_radius: f32,
    // The distance between the planet center and the top of the atmosphere
    top_radius: f32,
    // The density profile of air molecules, i.e. a function from altitude to
    // dimensionless values between 0 (null density) and 1 (maximum density).
    rayleigh_density: DensityProfile,
    // The scattering coefficient of air molecules at the altitude where their
    // density is maximum (usually the bottom of the atmosphere), as a function of
    // wavelength. The scattering coefficient at altitude h is equal to
    // 'rayleigh_scattering' times 'rayleigh_density' at this altitude.
    rayleigh_scattering: [3]f32,
    // The density profile of aerosols, i.e. a function from altitude to
    // dimensionless values between 0 (null density) and 1 (maximum density).
    mie_density: DensityProfile,
    // The scattering coefficient of aerosols at the altitude where their density
    // is maximum (usually the bottom of the atmosphere), as a function of
    // wavelength. The scattering coefficient at altitude h is equal to
    // 'mie_scattering' times 'mie_density' at this altitude.
    mie_scattering: [3]f32,
    // The extinction coefficient of aerosols at the altitude where their density
    // is maximum (usually the bottom of the atmosphere), as a function of
    // wavelength. The extinction coefficient at altitude h is equal to
    // 'mie_extinction' times 'mie_density' at this altitude.
    mie_extinction: [3]f32,
    // The asymetry parameter for the Cornette-Shanks phase function for the
    // aerosols.
    mie_phase_function_g: f32,
    // The density profile of air molecules that absorb light (e.g. ozone), i.e.
    // a function from altitude to dimensionless values between 0 (null density)
    // and 1 (maximum density).
    absorption_density: DensityProfile,
    // The extinction coefficient of molecules that absorb light (e.g. ozone) at
    // the altitude where their density is maximum, as a function of wavelength.
    // The extinction coefficient at altitude h is equal to
    // 'absorption_extinction' times 'absorption_density' at this altitude.
    absorption_extinction: [3]f32,
    // The average albedo of the ground.
    ground_albedo: [3]f32,
    // The cosine of the maximum Sun zenith angle for which atmospheric scattering
    // must be precomputed (for maximum precision, use the smallest Sun zenith
    // angle yielding negligible sky light radiance values. For instance, for the
    // Earth case, 102 degrees is a good choice - yielding mu_s_min = -0.2).
    mu_s_min: f32,
};

pub const AtmosphereRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    render_pass: renderer.RenderPass,

    atmosphere_info: AtmoshereInfo,

    frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    sky_atmosphere_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,

    multi_scattering_texture: renderer.TextureHandle,
    transmittance_lut_descriptor_set: [*c]graphics.DescriptorSet,
    multi_scattering_descriptor_set: [*c]graphics.DescriptorSet,
    sky_ray_marching_descriptor_set: [*c]graphics.DescriptorSet,

    // Mie Settings
    mie_scattering_length: f32 = undefined,
    mie_scattering_color: [3]f32 = undefined,
    mie_absorption_length: f32 = undefined,
    mie_absorption_color: [3]f32 = undefined,
    mie_scale_height: f32 = undefined,
    // Reyleigh Settings
    rayleigh_scattering_length: f32 = undefined,
    rayleigh_scattering_color: [3]f32 = undefined,
    rayleigh_scale_height: f32 = undefined,
    // Absorption Settings
    absorption_length: f32 = undefined,
    absorption_color: [3]f32 = undefined,
    // Atmosphere Settings
    atmosphere_height: f32 = undefined,
    current_multiple_scattering_factor: f32 = undefined,
    num_scattering_order: i32 = undefined,
    ground_albedo: [3]f32 = undefined,

    pub fn init(self: *AtmosphereRenderPass, rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) void {
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
                buffers[buffer_index] = rctx.createUniformBuffer(SkyAtmosphereConstantBuffer);
            }

            break :blk buffers;
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

        self.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .render_pass = undefined,
            .multi_scattering_texture = multi_scattering_texture,
            .frame_buffers = frame_buffers,
            .sky_atmosphere_buffers = sky_atmosphere_buffers,
            .transmittance_lut_descriptor_set = undefined,
            .multi_scattering_descriptor_set = undefined,
            .sky_ray_marching_descriptor_set = undefined,
            .atmosphere_info = undefined,
        };

        setupEarthAtmosphere(self);

        // Initialize UI variables
        {
            var mie_scattering: [3]f32 = undefined;
            @memcpy(&mie_scattering, &self.atmosphere_info.mie_scattering);

            const z_mie_scattering = zm.loadArr3(mie_scattering);
            self.mie_scattering_length = zm.length3(z_mie_scattering)[0];
            if (self.mie_scattering_length == 0.0) {
                self.mie_scattering_color = .{ 0.0, 0.0, 0.0 };
            } else {
                zm.storeArr3(&self.mie_scattering_color, zm.normalize3(z_mie_scattering));
            }

            const mie_absorption = [3]f32{
                @max(0.0, self.atmosphere_info.mie_extinction[0] - self.atmosphere_info.mie_scattering[0]),
                @max(0.0, self.atmosphere_info.mie_extinction[1] - self.atmosphere_info.mie_scattering[1]),
                @max(0.0, self.atmosphere_info.mie_extinction[2] - self.atmosphere_info.mie_scattering[2]),
            };
            const z_mie_absorption = zm.loadArr3(mie_absorption);
            self.mie_absorption_length = zm.length3(z_mie_absorption)[0];
            if (self.mie_absorption_length == 0.0) {
                self.mie_absorption_color = .{ 0.0, 0.0, 0.0 };
            } else {
                zm.storeArr3(&self.mie_absorption_color, zm.normalize3(z_mie_absorption));
            }

            var rayleigh_scattering: [3]f32 = undefined;
            @memcpy(&rayleigh_scattering, &self.atmosphere_info.rayleigh_scattering);
            const z_rayleigh_scattering = zm.loadArr3(rayleigh_scattering);
            self.rayleigh_scattering_length = zm.length3(z_rayleigh_scattering)[0];
            if (self.rayleigh_scattering_length == 0.0) {
                self.rayleigh_scattering_color = .{ 0.0, 0.0, 0.0 };
            } else {
                zm.storeArr3(&self.rayleigh_scattering_color, zm.normalize3(z_rayleigh_scattering));
            }

            self.atmosphere_height = self.atmosphere_info.top_radius - self.atmosphere_info.bottom_radius;
            self.mie_scale_height = -1.0 / self.atmosphere_info.mie_density.layers[1].exp_scale;
            self.rayleigh_scale_height = -1.0 / self.atmosphere_info.rayleigh_density.layers[1].exp_scale;
            const z_absorption_extinction = zm.loadArr3(self.atmosphere_info.absorption_extinction);
            self.absorption_length = zm.length3(z_absorption_extinction)[0];
            if (self.absorption_length == 0.0) {
                self.absorption_color = .{ 0.0, 0.0, 0.0 };
            } else {
                zm.storeArr3(&self.absorption_color, zm.normalize3(z_absorption_extinction));
            }

            self.num_scattering_order = 4;
            self.ground_albedo = .{ 0.0, 0.0, 0.0 };
        }

        createDescriptorSets(@ptrCast(self));
        prepareDescriptorSets(@ptrCast(self));

        self.render_pass = renderer.RenderPass{
            .create_descriptor_sets_fn = createDescriptorSets,
            .prepare_descriptor_sets_fn = prepareDescriptorSets,
            .unload_descriptor_sets_fn = unloadDescriptorSets,
            .render_imgui_fn = renderImGui,
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
        light: *const fd.DirectionalLight,
        rotation: *const fd.Rotation,
    });
    const z_sun_direction = zm.normalize4(zm.rotate(sun_comps.rotation.asZM(), zm.Vec{ 0, 0, 1, 0 }));
    const sun_light = sun_comps.light.*;

    // Update Frame buffer
    var frame_buffer_data: FrameBuffer = blk: {
        var frame_buffer_data: FrameBuffer = std.mem.zeroes(FrameBuffer);

        zm.storeMat(&frame_buffer_data.view_proj_mat, z_proj_view);
        frame_buffer_data.color = [4]f32{ 0.0, 1.0, 1.0, 1.0 };
        frame_buffer_data.resolution = [2]u32{ @intCast(self.renderer.window.frame_buffer_size[0]), @intCast(self.renderer.window.frame_buffer_size[1]) };
        frame_buffer_data.sun_illuminance = [3]f32{
            sun_light.color.r * sun_light.intensity, // * self.atmosphere_info.sky_exposure,
            sun_light.color.b * sun_light.intensity, // * self.atmosphere_info.sky_exposure,
            sun_light.color.g * sun_light.intensity, // * self.atmosphere_info.sky_exposure,
        };
        frame_buffer_data.scattering_max_path_depth = 4;
        frame_buffer_data.frame_time_sec = 0.0; // unused so far
        frame_buffer_data.time_sec = 0.0; // unused so far
        frame_buffer_data.ray_march_min_max_spp = [2]f32{ 4.0, 14.0 };

        const data = renderer.Slice{
            .data = @ptrCast(&frame_buffer_data),
            .size = @sizeOf(FrameBuffer),
        };
        self.renderer.updateBuffer(data, FrameBuffer, self.frame_buffers[frame_index]);

        break :blk frame_buffer_data;
    };

    // Update Sky Atmosphere Buffer
    {
        // Convert UI to physical data
        {
            self.atmosphere_info.mie_scattering = .{
                self.mie_scattering_color[0] * self.mie_scattering_length,
                self.mie_scattering_color[1] * self.mie_scattering_length,
                self.mie_scattering_color[2] * self.mie_scattering_length,
            };

            self.atmosphere_info.mie_extinction = .{
                self.atmosphere_info.mie_scattering[0] + self.mie_absorption_color[0] * self.mie_absorption_length,
                self.atmosphere_info.mie_scattering[1] + self.mie_absorption_color[1] * self.mie_absorption_length,
                self.atmosphere_info.mie_scattering[2] + self.mie_absorption_color[2] * self.mie_absorption_length,
            };

            self.atmosphere_info.rayleigh_scattering = .{
                self.rayleigh_scattering_color[0] * self.rayleigh_scattering_length,
                self.rayleigh_scattering_color[1] * self.rayleigh_scattering_length,
                self.rayleigh_scattering_color[2] * self.rayleigh_scattering_length,
            };

            self.atmosphere_info.absorption_extinction = .{
                self.absorption_color[0] * self.absorption_length,
                self.absorption_color[1] * self.absorption_length,
                self.absorption_color[2] * self.absorption_length,
            };

            self.atmosphere_info.top_radius = self.atmosphere_info.bottom_radius + self.atmosphere_height;
            self.atmosphere_info.mie_density.layers[1].exp_scale = -1.0 / self.mie_scale_height;
            self.atmosphere_info.rayleigh_density.layers[1].exp_scale = -1.0 / self.rayleigh_scale_height;
            @memcpy(&self.atmosphere_info.ground_albedo, &self.ground_albedo);
        }

        var cb = std.mem.zeroes(SkyAtmosphereConstantBuffer);
        @memcpy(&cb.solar_irradiance, &self.atmosphere_info.solar_irradiance);
        cb.sun_angular_radius = self.atmosphere_info.sun_angular_radius;
        @memcpy(&cb.absorption_extinction, &self.atmosphere_info.absorption_extinction);
        cb.mu_s_min = self.atmosphere_info.mu_s_min;

        // TODO: Find a way to do this in zig
        // @memcpy(&cb.rayleigh_density, &self.atmosphere_info.rayleigh_density);
        cb.rayleigh_density = .{
            self.atmosphere_info.rayleigh_density.layers[0].width,
            self.atmosphere_info.rayleigh_density.layers[0].exp_term,
            self.atmosphere_info.rayleigh_density.layers[0].exp_scale,
            self.atmosphere_info.rayleigh_density.layers[0].linear_term,
            self.atmosphere_info.rayleigh_density.layers[0].constant_term,
            self.atmosphere_info.rayleigh_density.layers[1].width,
            self.atmosphere_info.rayleigh_density.layers[1].exp_term,
            self.atmosphere_info.rayleigh_density.layers[1].exp_scale,
            self.atmosphere_info.rayleigh_density.layers[1].linear_term,
            self.atmosphere_info.rayleigh_density.layers[1].constant_term,
            42.0,
            42.0,
        };
        // TODO: Find a way to do this in zig
        // @memcpy(&cb.mie_density, &self.atmosphere_info.mie_density);
        cb.mie_density = .{
            self.atmosphere_info.mie_density.layers[0].width,
            self.atmosphere_info.mie_density.layers[0].exp_term,
            self.atmosphere_info.mie_density.layers[0].exp_scale,
            self.atmosphere_info.mie_density.layers[0].linear_term,
            self.atmosphere_info.mie_density.layers[0].constant_term,
            self.atmosphere_info.mie_density.layers[1].width,
            self.atmosphere_info.mie_density.layers[1].exp_term,
            self.atmosphere_info.mie_density.layers[1].exp_scale,
            self.atmosphere_info.mie_density.layers[1].linear_term,
            self.atmosphere_info.mie_density.layers[1].constant_term,
            42.0,
            42.0,
        };
        // TODO: Find a way to do this in zig
        // @memcpy(&cb.absorption_density, &self.atmosphere_info.absorption_density);
        cb.absorption_density = .{
            self.atmosphere_info.absorption_density.layers[0].width,
            self.atmosphere_info.absorption_density.layers[0].exp_term,
            self.atmosphere_info.absorption_density.layers[0].exp_scale,
            self.atmosphere_info.absorption_density.layers[0].linear_term,
            self.atmosphere_info.absorption_density.layers[0].constant_term,
            self.atmosphere_info.absorption_density.layers[1].width,
            self.atmosphere_info.absorption_density.layers[1].exp_term,
            self.atmosphere_info.absorption_density.layers[1].exp_scale,
            self.atmosphere_info.absorption_density.layers[1].linear_term,
            self.atmosphere_info.absorption_density.layers[1].constant_term,
            42.0,
            42.0,
        };

        cb.mie_phase_function_g = self.atmosphere_info.mie_phase_function_g;
        @memcpy(&cb.rayleigh_scattering, &self.atmosphere_info.rayleigh_scattering);
        @memcpy(&cb.mie_scattering, &self.atmosphere_info.mie_scattering);
        cb.mie_absorption = [3]f32{
            @max(0.0, self.atmosphere_info.mie_extinction[0] - self.atmosphere_info.mie_scattering[0]),
            @max(0.0, self.atmosphere_info.mie_extinction[1] - self.atmosphere_info.mie_scattering[1]),
            @max(0.0, self.atmosphere_info.mie_extinction[2] - self.atmosphere_info.mie_scattering[2]),
        };
        @memcpy(&cb.mie_extinction, &self.atmosphere_info.mie_extinction);
        @memcpy(&cb.ground_albedo, &self.atmosphere_info.ground_albedo);
        cb.bottom_radius = self.atmosphere_info.bottom_radius;
        cb.top_radius = self.atmosphere_info.top_radius;
        cb.multiple_scattering_factor = self.current_multiple_scattering_factor;
        cb.multi_scattering_LUT_res = multi_scattering_texture_resolution;

        cb.transmittance_texture_width = transmittance_texture_width;
        cb.transmittance_texture_height = transmittance_texture_height;
        cb.irradiance_texture_width = irradiance_texture_width;
        cb.irradiance_texture_height = irradiance_texture_height;
        cb.scattering_texture_r_size = scattering_texture_r_size;
        cb.scattering_texture_mu_size = scattering_texture_mu_size;
        cb.scattering_texture_mu_s_size = scattering_texture_mu_s_size;
        cb.scattering_texture_nu_size = scattering_texture_nu_size;
        cb.sky_spectral_radiance_to_luminance = [3]f32{ 114974.916437, 71305.954816, 65310.548555 };
        cb.sun_spectral_radiance_to_luminance = [3]f32{ 98242.786222, 69954.398112, 66475.012354 };
        zm.storeMat(&cb.sky_view_proj_mat, z_proj_view);
        zm.storeMat(&cb.sky_inv_view_proj_mat, zm.inverse(z_proj_view));
        zm.storeMat(&cb.sky_inv_view_mat, zm.inverse(z_view));
        zm.storeMat(&cb.sky_inv_proj_mat, zm.inverse(z_proj));
        @memcpy(&cb.camera, &camera_pos);
        zm.storeArr3(&cb.view_ray, z_cam_direction);
        zm.storeArr3(&cb.sun_direction, -z_sun_direction);
        const data = renderer.Slice{
            .data = @ptrCast(&cb),
            .size = @sizeOf(SkyAtmosphereConstantBuffer),
        };
        self.renderer.updateBuffer(data, SkyAtmosphereConstantBuffer, self.sky_atmosphere_buffers[frame_index]);
    }

    // Render Transmittance LUT
    {
        var input_barriers = [_]graphics.RenderTargetBarrier{
            graphics.RenderTargetBarrier.init(self.renderer.transmittance_lut, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
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
        bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.renderer.transmittance_lut;
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
            graphics.RenderTargetBarrier.init(self.renderer.transmittance_lut, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
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
            params[1].__union_field3.ppTextures = @ptrCast(&self.renderer.transmittance_lut.*.pTexture);
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
            var multi_scattering_texture = self.renderer.getTexture(self.multi_scattering_texture);

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "FrameBuffer";
            params[0].__union_field3.ppBuffers = @ptrCast(&frame_buffer);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "SkyAtmosphereBuffer";
            params[1].__union_field3.ppBuffers = @ptrCast(&sky_atmosphere_buffer);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "view_depth_texture";
            params[2].__union_field3.ppTextures = @ptrCast(&self.renderer.depth_buffer.*.pTexture);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "transmittance_lut_texture";
            params[3].__union_field3.ppTextures = @ptrCast(&self.renderer.transmittance_lut.*.pTexture);
            params[4] = std.mem.zeroes(graphics.DescriptorData);
            params[4].pName = "multi_scat_texture";
            params[4].__union_field3.ppTextures = @ptrCast(&multi_scattering_texture);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(frame_index), self.sky_ray_marching_descriptor_set, 5, @ptrCast(&params));
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

fn renderImGui(user_data: *anyopaque) void {
    if (zgui.collapsingHeader("Atmosphere Scattering", .{})) {
        const self: *AtmosphereRenderPass = @ptrCast(@alignCast(user_data));

        _ = zgui.dragFloat("Mie Phase", .{ .v = &self.atmosphere_info.mie_phase_function_g, .cfmt = "%.4f", .min = 0.0, .max = 0.999, .speed = 0.001 });
        _ = zgui.dragInt("Scattering Order", .{ .v = &self.num_scattering_order, .min = 1, .max = 50 });

        _ = zgui.colorEdit3("Mie Scattering Coefficient", .{ .col = &self.mie_scattering_color });
        _ = zgui.dragFloat("Mie Scattering Scale", .{ .v = &self.mie_scattering_length, .cfmt = "%.5f", .min = 0.00001, .max = 0.1, .speed = 0.00001 });
        _ = zgui.colorEdit3("Mie Absorption Coefficient", .{ .col = &self.mie_absorption_color });
        _ = zgui.dragFloat("Mie Absorption Scale", .{ .v = &self.mie_absorption_length, .cfmt = "%.5f", .min = 0.00001, .max = 0.1, .speed = 0.00001 });
        _ = zgui.colorEdit3("Rayleigh Scattering Coefficient", .{ .col = &self.rayleigh_scattering_color });
        _ = zgui.dragFloat("Rayleigh Scattering Scale", .{ .v = &self.rayleigh_scattering_length, .cfmt = "%.5f", .min = 0.00001, .max = 0.1, .speed = 0.00001 });
        _ = zgui.colorEdit3("Absorption Coefficient", .{ .col = &self.absorption_color });
        _ = zgui.dragFloat("Absorption Scale", .{ .v = &self.absorption_length, .cfmt = "%.5f", .min = 0.00001, .max = 0.1, .speed = 0.00001 });
        _ = zgui.dragFloat("Planet Radius", .{ .v = &self.atmosphere_info.bottom_radius, .min = 100.0, .max = 8000.0 });
        _ = zgui.dragFloat("Atmosphere Height", .{ .v = &self.atmosphere_height, .min = 10.0, .max = 150.0 });
        _ = zgui.dragFloat("Mie Scale Height", .{ .v = &self.mie_scale_height, .min = 0.5, .max = 20.0 });
        _ = zgui.dragFloat("Rayleigh Scale Height", .{ .v = &self.rayleigh_scale_height, .min = 0.5, .max = 20.0 });
        _ = zgui.colorEdit3("Ground Albedo", .{ .col = &self.ground_albedo });

        _ = zgui.dragFloat("Sun Angular Radius (Deg)", .{ .v = &self.atmosphere_info.sun_angular_radius, .cfmt = "%.4f", .min = 0.0001, .max = 0.1, .speed = 0.0001 });
    }
}

fn setupEarthAtmosphere(self: *AtmosphereRenderPass) void {
    // Values shown here are the result of integration over wavelength power spectrum integrated with paricular function.
    // Refer to https://github.com/ebruneton/precomputed_atmospheric_scattering for details.

    // All units in kilometers
    const earth_bottom_radius: f32 = 6360.0;
    const earth_top_radius: f32 = 6460.0; // 100km atmosphere radius, less edge visible and it contain 99.99% of the atmosphere medium https://en.wikipedia.org/wiki/K%C3%A1rm%C3%A1n_line
    const earth_rayleigh_scale_height: f32 = 8.0;
    const earth_mie_scale_height: f32 = 1.2;

    // Sun - This should not be part of the sky model...
    //sky_atmosphere.solar_irradiance = { 1.474000f, 1.850400f, 1.911980f };
    self.atmosphere_info.solar_irradiance = [3]f32{ 1.0, 1.0, 1.0 }; // Using a normalise sun illuminance. This is to make sure the LUTs acts as a transfert factor to apply the runtime computed sun irradiance over.
    self.atmosphere_info.sun_angular_radius = 0.004675;

    // Earth
    self.atmosphere_info.bottom_radius = earth_bottom_radius;
    self.atmosphere_info.top_radius = earth_top_radius;
    self.atmosphere_info.ground_albedo = [3]f32{ 0.0, 0.0, 0.0 };

    // Raleigh scattering
    self.atmosphere_info.rayleigh_density.layers[0] = .{ .width = 0.0, .exp_term = 0.0, .exp_scale = 0.0, .linear_term = 0.0, .constant_term = 0.0 };
    self.atmosphere_info.rayleigh_density.layers[1] = .{ .width = 0.0, .exp_term = 1.0, .exp_scale = -1.0 / earth_rayleigh_scale_height, .linear_term = 0.0, .constant_term = 0.0 };
    self.atmosphere_info.rayleigh_scattering = [3]f32{ 0.005802, 0.013558, 0.033100 }; // 1/km

    // Mie scattering
    self.atmosphere_info.mie_density.layers[0] = .{ .width = 0.0, .exp_term = 0.0, .exp_scale = 0.0, .linear_term = 0.0, .constant_term = 0.0 };
    self.atmosphere_info.mie_density.layers[1] = .{ .width = 0.0, .exp_term = 1.0, .exp_scale = -1.0 / earth_mie_scale_height, .linear_term = 0.0, .constant_term = 0.0 };
    self.atmosphere_info.mie_scattering = [3]f32{ 0.003996, 0.003996, 0.003996 }; // 1/km
    self.atmosphere_info.mie_extinction = [3]f32{ 0.004440, 0.004440, 0.004440 }; // 1/km
    self.atmosphere_info.mie_phase_function_g = 0.8;

    // Ozone absorption
    self.atmosphere_info.absorption_density.layers[0] = .{ .width = 25.0, .exp_term = 0.0, .exp_scale = 0.0, .linear_term = 1.0 / 15.0, .constant_term = -2.0 / 3.0 };
    self.atmosphere_info.absorption_density.layers[1] = .{ .width = 0.0, .exp_term = 0.0, .exp_scale = 0.0, .linear_term = -1.0 / 15.0, .constant_term = 8.0 / 3.0 };
    self.atmosphere_info.absorption_extinction = [3]f32{ 0.000650, 0.001881, 0.000085 }; // 1/km

    const max_sun_zenith_angle: f32 = std.math.pi * 120.0 / 180.0; // (use_half_precision_ ? 102.0 : 120.0) / 180.0 * kPi;
    self.atmosphere_info.mu_s_min = std.math.cos(max_sun_zenith_angle);
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
    graphics.removeDescriptorSet(self.renderer.renderer, self.sky_ray_marching_descriptor_set);
}
