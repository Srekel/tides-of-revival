const std = @import("std");
const assert = std.debug.assert;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const Pool = @import("zpool").Pool;
const zd3d12 = @import("zd3d12");
const zglfw = @import("zglfw");
const zm = @import("zmath");
const zpix = @import("zpix");
const zstbi = @import("zstbi");
const zwin32 = @import("zwin32");
const d2d1 = zwin32.d2d1;
const d3d12 = zwin32.d3d12;
const dds_loader = zwin32.dds_loader;
const dwrite = zwin32.dwrite;
const dxgi = zwin32.dxgi;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const w32 = zwin32.w32;
const buffer_module = @import("d3d12/buffer.zig");
const config = @import("../config/config.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const IdLocalHashMapContext = @import("../core/core.zig").IdLocalHashMapContext;
const mesh_loader = @import("mesh_loader.zig");
const profiler_module = @import("d3d12/profiler.zig");
const renderer_types = @import("renderer_types.zig");
const tides_math = @import("../core/math.zig");
const util = @import("../util.zig");

pub const Profiler = profiler_module.Profiler;
pub const ProfileData = profiler_module.ProfileData;

const Buffer = buffer_module.Buffer;
const BufferPool = buffer_module.BufferPool;
pub const BufferDesc = buffer_module.BufferDesc;
pub const BufferHandle = buffer_module.BufferHandle;
const IndexType = renderer_types.IndexType;
const Vertex = renderer_types.Vertex;
const UIIndexType = renderer_types.UIIndexType;
const UIVertex = renderer_types.UIVertex;
const Mesh = renderer_types.Mesh;
const SubMesh = renderer_types.SubMesh;
pub const Texture = renderer_types.Texture;
pub const TextureDesc = renderer_types.TextureDesc;

// Mesh Pool
const MeshPool = Pool(16, 16, Mesh, struct { obj: Mesh });
pub const MeshHandle = MeshPool.Handle;
const MeshHashMap = std.AutoHashMap(IdLocal, MeshHandle);

// Texture Pool
const TexturePool = Pool(16, 16, Texture, struct { obj: Texture });
pub const TextureHandle = TexturePool.Handle;
const TextureHashMap = std.AutoHashMap(IdLocal, TextureHandle);

// Material Pool
const MaterialPool = Pool(16, 16, fd.PBRMaterial, struct { obj: fd.PBRMaterial });
pub const MaterialHandle = MaterialPool.Handle;
const MaterialHashMap = std.AutoHashMap(IdLocal, MaterialHandle);

pub export const D3D12SDKVersion: u32 = 610;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

pub const ViewMode = enum(u32) {
    lit = 0,
    albedo = 1,
    world_normal = 2,
    metallic = 3,
    roughness = 4,
    ao = 5,
    depth = 6,
};

pub const RenderTargetsUniforms = struct {
    gbuffer_0_index: u32,
    gbuffer_1_index: u32,
    gbuffer_2_index: u32,
    depth_texture_index: u32,
    scene_color_texture_index: u32,
};

pub const FrameUniforms = struct {
    view_projection: zm.Mat,
    view_projection_inverted: zm.Mat,
    camera_position: [3]f32,
};

pub const TonemapperUniforms = struct {
    scene_color_texture_index: u32,
    bloom_texture_index: u32,
};

pub const DepthBasedFogUniforms = struct {
    fog_color: [3]f32,
    fog_radius: f32,
    fog_fade_rate: f32,
    fog_density: f32,
    scene_color_texture_index: u32,
    depth_texture_index: u32,
    gbuffer_0_texture_index: u32,
    _padding: [3]f32,
};

pub const DownsampleUniforms = struct {
    source_resolution: [2]f32,
    mip_level: u32,
};

pub const UpsampleBlurUniforms = struct {
    source_resolution: [2]f32,
    sample_scale: f32,
};

pub const UIUniforms = struct {
    screen_to_clip: zm.Mat,
    ui_transform_buffer_index: u32,
};

const UIImageGPU = struct {
    rect: [4]f32,
    color: [4]f32,
    texture_index: u32,
    _padding: [3]f32,
};

pub const UIImage = struct {
    rect: [4]f32,
    color: [4]f32,
    texture: TextureHandle,
};

pub const SceneUniforms = extern struct {
    main_light_direction: [3]f32,
    point_lights_buffer_index: u32,
    main_light_color: [3]f32,
    point_lights_count: u32,
    main_light_intensity: f32,
    prefiltered_env_texture_max_lods: f32,
    env_texture_index: u32,
    irradiance_texture_index: u32,
    prefiltered_env_texture_index: u32,
    brdf_integration_texture_index: u32,
    ambient_light_intensity: f32,
    padding: f32,
};

pub const ViewModeUniforms = extern struct {
    view_mode: u32,
};

const UITextFormatHashMap = std.AutoHashMap(u32, *dwrite.ITextFormat);

pub const UIRect = struct {
    left: f32,
    top: f32,
    right: f32,
    bottom: f32,
};

pub const UILabel = struct {
    label: []const u8,
    rect: UIRect,
    font_size: u32,
    color: [4]f32,
};

const ResourceView = struct {
    resource: zd3d12.ResourceHandle,
    view: d3d12.CPU_DESCRIPTOR_HANDLE,
    persistent_descriptor: zd3d12.PersistentDescriptor,
};

const HDRIConstBuffer = struct {
    object_to_view: zm.Mat,
    vertex_buffer_index: u32,
    vertex_offset: i32,
};

const env_texture_resolution = 512;
const irradiance_texture_resolution = 64;
const prefiltered_env_texture_resolution = 256;
const prefiltered_env_texture_num_mip_levels = 6;
const brdf_integration_texture_resolution = 512;

pub const FrameStats = struct {
    time: f64,
    delta_time: f32,
    fps: f32,
    average_cpu_time: f32,
    timer: std.time.Timer,
    previous_time_ns: u64,
    fps_refresh_time_ns: u64,
    frame_counter: u64,

    pub fn init() FrameStats {
        return .{
            .time = 0.0,
            .delta_time = 0.0,
            .fps = 0.0,
            .average_cpu_time = 0.0,
            .timer = std.time.Timer.start() catch unreachable,
            .previous_time_ns = 0,
            .fps_refresh_time_ns = 0,
            .frame_counter = 0,
        };
    }

    pub fn update(self: *FrameStats) void {
        const now_ns = self.timer.read();
        self.time = @as(f64, @floatFromInt(now_ns)) / std.time.ns_per_s;
        self.delta_time = @as(f32, @floatFromInt(now_ns - self.previous_time_ns)) / std.time.ns_per_s;
        self.previous_time_ns = now_ns;

        if ((now_ns - self.fps_refresh_time_ns) >= std.time.ns_per_s) {
            const t = @as(f64, @floatFromInt(now_ns - self.fps_refresh_time_ns)) / std.time.ns_per_s;
            const fps = @as(f64, @floatFromInt(self.frame_counter)) / t;
            const ms = (1.0 / fps) * 1000.0;

            self.fps = @as(f32, @floatCast(fps));
            self.average_cpu_time = @as(f32, @floatCast(ms));
            self.fps_refresh_time_ns = now_ns;
            self.frame_counter = 0;
        }
        self.frame_counter += 1;
    }
};

pub const PipelineInfo = struct {
    pipeline_handle: zd3d12.PipelineHandle,
};

const PipelineHashMap = std.HashMap(IdLocal, PipelineInfo, IdLocalHashMapContext, 80);

pub const D3D12State = struct {
    pub const num_buffered_frames = zd3d12.GraphicsContext.max_num_buffered_frames;
    pub const point_lights_count_max: u32 = 1000;
    pub const downsample_rt_count: u32 = 10;
    const ui_instances_count_max: u32 = 4096;

    gctx: zd3d12.GraphicsContext,
    mipgen_rgba8: zd3d12.MipmapGenerator,
    mipgen_rgba16f: zd3d12.MipmapGenerator,
    gpu_profiler: Profiler,
    gpu_frame_profiler_index: u64 = undefined,
    view_mode: ViewMode = .lit,

    frame_allocator_state: std.heap.ArenaAllocator,
    frame_allocator: std.mem.Allocator,

    stats: FrameStats,
    stats_brush: *d2d1.ISolidColorBrush,
    stats_text_format: *dwrite.ITextFormat,
    ui_label_brush: *d2d1.ISolidColorBrush,
    ui_text_formats_map: UITextFormatHashMap,
    ui_labels: std.ArrayList(UILabel),

    depth_rt: ?RenderTarget,

    gbuffer_0: ?RenderTarget,
    gbuffer_1: ?RenderTarget,
    gbuffer_2: ?RenderTarget,

    scene_color_rt: ?RenderTarget,
    post_process_rt: ?RenderTarget,
    downsample_rts: [downsample_rt_count]?RenderTarget,

    // NOTE(gmodarelli): Temporary logo resources.
    // TODO(gmodarelli): Move these to a separate system
    splash_texture: TextureHandle,
    logo_texture: TextureHandle,
    wwise_logo_texture: TextureHandle,
    end_screen_texture: TextureHandle,
    splash_screen_duration: f32,
    splash_screen_fade_out_duration: f32,
    splash_screen_accumulated_time: f32,
    end_screen_fade_in_duration: f32,
    end_screen_accumulated_time: f32,

    // NOTE(gmodarelli): just a test, these textures should
    // be loaded by a "sky light" component
    // IBL generated from HRDI
    env_texture: ResourceView,
    irradiance_texture: ResourceView,
    prefiltered_env_texture: ResourceView,
    brdf_integration_texture: TextureHandle,

    texture_pool: TexturePool,
    texture_hash: TextureHashMap,
    small_textures_heap: *d3d12.IHeap,
    small_textures_heap_offset: u64,

    buffer_pool: BufferPool,
    pipelines: PipelineHashMap,

    material_pool: MaterialPool,
    material_hash: MaterialHashMap,
    mesh_hash: MeshHashMap,
    mesh_pool: MeshPool,
    skybox_mesh: MeshHandle,

    quad_index_buffer: BufferHandle,
    ui_image_buffers: [num_buffered_frames]BufferHandle,
    ui_images: std.ArrayList(UIImageGPU),

    main_light: renderer_types.DirectionalLightGPU,
    point_lights_buffers: [num_buffered_frames]BufferHandle,
    point_lights_count: [num_buffered_frames]u32,

    pub fn resize(self: *D3D12State, width: u32, height: u32) void {
        if (width == 0 or height == 0) {
            return;
        }

        if (self.gctx.viewport_width == width and self.gctx.viewport_height == height) {
            return;
        }

        var gctx = &self.gctx;

        _ = self.stats_brush.Release();
        _ = self.stats_text_format.Release();

        _ = self.ui_label_brush.Release();
        var iter = self.ui_text_formats_map.keyIterator();
        while (iter.next()) |key| {
            _ = self.ui_text_formats_map.get(key.*).?.Release();
        }

        gctx.resize(width, height);

        self.stats_brush = blk: {
            var brush: ?*d2d1.ISolidColorBrush = null;
            hrPanicOnFail(gctx.d2d.?.context.CreateSolidColorBrush(
                &.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                null,
                &brush,
            ));
            break :blk brush.?;
        };

        // Create Direct2D text format which will be needed to display text.
        self.stats_text_format = blk: {
            var text_format: ?*dwrite.ITextFormat = null;
            hrPanicOnFail(gctx.d2d.?.dwrite_factory.CreateTextFormat(
                L("Verdana"),
                null,
                .BOLD,
                .NORMAL,
                .NORMAL,
                12.0,
                L("en-us"),
                &text_format,
            ));
            break :blk text_format.?;
        };
        hrPanicOnFail(self.stats_text_format.SetTextAlignment(.LEADING));
        hrPanicOnFail(self.stats_text_format.SetParagraphAlignment(.NEAR));

        self.ui_label_brush = blk: {
            var brush: ?*d2d1.ISolidColorBrush = null;
            hrPanicOnFail(gctx.d2d.?.context.CreateSolidColorBrush(
                &.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
                null,
                &brush,
            ));
            break :blk brush.?;
        };

        iter = self.ui_text_formats_map.keyIterator();
        while (iter.next()) |key| {
            const text_format = blk: {
                var text_format: ?*dwrite.ITextFormat = null;
                hrPanicOnFail(gctx.d2d.?.dwrite_factory.CreateTextFormat(
                    L("Verdana"),
                    null,
                    .BOLD,
                    .NORMAL,
                    .NORMAL,
                    @floatFromInt(key.*),
                    L("en-us"),
                    &text_format,
                ));
                break :blk text_format.?;
            };
            hrPanicOnFail(text_format.SetTextAlignment(.LEADING));
            hrPanicOnFail(text_format.SetParagraphAlignment(.NEAR));

            self.ui_text_formats_map.put(key.*, text_format) catch unreachable;
        }

        createRenderTargets(self);
    }

    pub fn getPipeline(self: *D3D12State, pipeline_id: IdLocal) ?PipelineInfo {
        return self.pipelines.get(pipeline_id);
    }

    pub fn createBuffer(self: *D3D12State, bufferDesc: BufferDesc) !BufferHandle {
        var buffer: Buffer = undefined;
        buffer.state = bufferDesc.state;

        const desc = d3d12.RESOURCE_DESC.initBuffer(bufferDesc.size);
        buffer.resource = self.gctx.createCommittedResource(
            .DEFAULT,
            .{},
            &desc,
            d3d12.RESOURCE_STATES.COMMON,
            null,
        ) catch |err| hrPanic(err);

        var resource = self.gctx.lookupResource(buffer.resource).?;
        _ = resource.SetName(bufferDesc.name);

        if (bufferDesc.has_srv and bufferDesc.persistent) {
            buffer.persistent = true;
            buffer.has_srv = true;

            const srv_allocation = self.gctx.allocatePersistentGpuDescriptors(1);
            self.gctx.device.CreateShaderResourceView(
                self.gctx.lookupResource(buffer.resource).?,
                &d3d12.SHADER_RESOURCE_VIEW_DESC{
                    .ViewDimension = .BUFFER,
                    .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                    .Format = .R32_TYPELESS,
                    .u = .{
                        .Buffer = .{
                            .FirstElement = 0,
                            .NumElements = @as(u32, @intCast(@divExact(bufferDesc.size, 4))),
                            .StructureByteStride = 0,
                            .Flags = .{ .RAW = true },
                        },
                    },
                },
                srv_allocation.cpu_handle,
            );

            buffer.persistent_descriptor = srv_allocation;
        }

        return self.buffer_pool.addBuffer(buffer);
    }

    pub fn destroyBuffer(self: *D3D12State, handle: BufferHandle) void {
        self.buffer_pool.destroyBuffer(handle, &self.gctx);
    }

    pub inline fn lookupBuffer(self: *D3D12State, handle: BufferHandle) ?*Buffer {
        return self.buffer_pool.lookupBuffer(handle);
    }

    pub fn scheduleUploadDataToBuffer(self: *D3D12State, comptime T: type, buffer_handle: BufferHandle, buffer_offset: u64, data: []T) u64 {
        // TODO: Schedule the upload instead of uploading immediately
        self.gctx.beginFrame();

        const offset = self.uploadDataToBuffer(T, buffer_handle, buffer_offset, data);

        self.gctx.endFrame();
        self.gctx.finishGpuCommands();

        return offset;
    }

    pub fn uploadDataToBuffer(self: *D3D12State, comptime T: type, buffer_handle: BufferHandle, buffer_offset: u64, data: []T) u64 {
        const buffer = self.buffer_pool.lookupBuffer(buffer_handle);
        if (buffer == null)
            return 0;

        self.gctx.addTransitionBarrier(buffer.?.resource, .{ .COPY_DEST = true });
        self.gctx.flushResourceBarriers();

        const upload_buffer_region = self.gctx.allocateUploadBufferRegion(T, @as(u32, @intCast(data.len)));
        std.mem.copy(T, upload_buffer_region.cpu_slice[0..data.len], data[0..data.len]);

        // NOTE(gmodarelli): Let's have zd3d12 return the aligned size instead
        const alloc_alignment: u64 = 512;
        const size = data.len * @sizeOf(T);
        const aligned_size = (size + (alloc_alignment - 1)) & ~(alloc_alignment - 1);

        self.gctx.cmdlist.CopyBufferRegion(
            self.gctx.lookupResource(buffer.?.resource).?,
            buffer_offset,
            upload_buffer_region.buffer,
            upload_buffer_region.buffer_offset,
            upload_buffer_region.cpu_slice.len * @sizeOf(@TypeOf(upload_buffer_region.cpu_slice[0])),
        );

        self.gctx.addTransitionBarrier(buffer.?.resource, buffer.?.state);
        self.gctx.flushResourceBarriers();

        return aligned_size;
    }

    pub fn generateIBLTextures(self: *D3D12State, hdri_path: []const u8, arena: std.mem.Allocator) !void {
        self.gctx.beginFrame();

        const equirect_texture = blk: {
            zstbi.setFlipVerticallyOnLoad(true);

            const pathname = std.fs.path.joinZ(arena, &.{
                std.fs.selfExeDirPathAlloc(arena) catch unreachable,
                hdri_path,
            }) catch unreachable;

            var image = zstbi.Image.loadFromFile(pathname, 4) catch unreachable;
            defer {
                image.deinit();
                zstbi.setFlipVerticallyOnLoad(false);
            }

            const equirect_texture = .{
                .resource = self.gctx.createCommittedResource(
                    .DEFAULT,
                    .{},
                    &d3d12.RESOURCE_DESC.initTex2d(.R16G16B16A16_FLOAT, image.width, image.height, 1),
                    .{ .COPY_DEST = true },
                    null,
                ) catch |err| hrPanic(err),
                .view = self.gctx.allocateCpuDescriptors(.CBV_SRV_UAV, 1),
            };
            self.gctx.device.CreateShaderResourceView(
                self.gctx.lookupResource(equirect_texture.resource).?,
                null,
                equirect_texture.view,
            );

            self.gctx.updateTex2dSubresource(
                equirect_texture.resource,
                0,
                image.data,
                image.width * @sizeOf(f16) * 4,
            );

            self.gctx.addTransitionBarrier(equirect_texture.resource, .{ .PIXEL_SHADER_RESOURCE = true });
            self.gctx.flushResourceBarriers();

            break :blk equirect_texture;
        };

        const env_texture = .{
            .resource = self.gctx.createCommittedResource(
                .DEFAULT,
                .{},
                &d3d12.RESOURCE_DESC{
                    .Dimension = .TEXTURE2D,
                    .Alignment = 0,
                    .Width = env_texture_resolution,
                    .Height = env_texture_resolution,
                    .DepthOrArraySize = 6,
                    .MipLevels = 0,
                    .Format = .R16G16B16A16_FLOAT,
                    .SampleDesc = .{ .Count = 1, .Quality = 0 },
                    .Layout = .UNKNOWN,
                    .Flags = .{ .ALLOW_RENDER_TARGET = true },
                },
                .{ .COPY_DEST = true },
                null,
            ) catch |err| hrPanic(err),
            .view = self.gctx.allocateCpuDescriptors(.CBV_SRV_UAV, 1),
            .persistent_descriptor = self.gctx.allocatePersistentGpuDescriptors(1),
        };

        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(env_texture.resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = .UNKNOWN,
                .ViewDimension = .TEXTURECUBE,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .TextureCube = .{
                        .MipLevels = 0xffff_ffff,
                        .MostDetailedMip = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            env_texture.view,
        );

        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(env_texture.resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = .R16G16B16A16_FLOAT,
                .ViewDimension = .TEXTURECUBE,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .TextureCube = .{
                        .MipLevels = 0xffff_ffff,
                        .MostDetailedMip = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            env_texture.persistent_descriptor.cpu_handle,
        );

        const irradiance_texture = .{
            .resource = self.gctx.createCommittedResource(
                .DEFAULT,
                .{},
                &d3d12.RESOURCE_DESC{
                    .Dimension = .TEXTURE2D,
                    .Alignment = 0,
                    .Width = irradiance_texture_resolution,
                    .Height = irradiance_texture_resolution,
                    .DepthOrArraySize = 6,
                    .MipLevels = 0,
                    .Format = .R16G16B16A16_FLOAT,
                    .SampleDesc = .{ .Count = 1, .Quality = 0 },
                    .Layout = .UNKNOWN,
                    .Flags = .{ .ALLOW_RENDER_TARGET = true },
                },
                .{ .COPY_DEST = true },
                null,
            ) catch |err| hrPanic(err),
            .view = self.gctx.allocateCpuDescriptors(.CBV_SRV_UAV, 1),
            .persistent_descriptor = self.gctx.allocatePersistentGpuDescriptors(1),
        };

        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(irradiance_texture.resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = .UNKNOWN,
                .ViewDimension = .TEXTURECUBE,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .TextureCube = .{
                        .MipLevels = 0xffff_ffff,
                        .MostDetailedMip = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            irradiance_texture.view,
        );

        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(irradiance_texture.resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = .UNKNOWN,
                .ViewDimension = .TEXTURECUBE,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .TextureCube = .{
                        .MipLevels = 0xffff_ffff,
                        .MostDetailedMip = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            irradiance_texture.persistent_descriptor.cpu_handle,
        );

        const prefiltered_env_texture = .{
            .resource = self.gctx.createCommittedResource(
                .DEFAULT,
                .{},
                &d3d12.RESOURCE_DESC{
                    .Dimension = .TEXTURE2D,
                    .Alignment = 0,
                    .Width = prefiltered_env_texture_resolution,
                    .Height = prefiltered_env_texture_resolution,
                    .DepthOrArraySize = 6,
                    .MipLevels = prefiltered_env_texture_num_mip_levels,
                    .Format = .R16G16B16A16_FLOAT,
                    .SampleDesc = .{ .Count = 1, .Quality = 0 },
                    .Layout = .UNKNOWN,
                    .Flags = .{ .ALLOW_RENDER_TARGET = true },
                },
                .{ .COPY_DEST = true },
                null,
            ) catch |err| hrPanic(err),
            .view = self.gctx.allocateCpuDescriptors(.CBV_SRV_UAV, 1),
            .persistent_descriptor = self.gctx.allocatePersistentGpuDescriptors(1),
        };

        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(prefiltered_env_texture.resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = .UNKNOWN,
                .ViewDimension = .TEXTURECUBE,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .TextureCube = .{
                        .MipLevels = prefiltered_env_texture_num_mip_levels,
                        .MostDetailedMip = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            prefiltered_env_texture.view,
        );

        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(prefiltered_env_texture.resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = .UNKNOWN,
                .ViewDimension = .TEXTURECUBE,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .TextureCube = .{
                        .MipLevels = prefiltered_env_texture_num_mip_levels,
                        .MostDetailedMip = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            prefiltered_env_texture.persistent_descriptor.cpu_handle,
        );

        self.gctx.flushResourceBarriers();

        var mesh = self.lookupMesh(self.skybox_mesh).?;

        self.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
        const index_buffer = self.lookupBuffer(mesh.index_buffer);
        const index_buffer_resource = self.gctx.lookupResource(index_buffer.?.resource);
        self.gctx.cmdlist.IASetIndexBuffer(&.{
            .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
            .SizeInBytes = @as(c_uint, @intCast(index_buffer_resource.?.GetDesc().Width)),
            .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
        });

        //
        // Generate env. (cube) texture content.
        //
        zpix.beginEvent(self.gctx.cmdlist, "Generate Env Cubemap");
        {
            const pipeline_info = self.getPipeline(IdLocal.init("generate_env_texture"));
            self.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);
            self.gctx.cmdlist.SetGraphicsRootDescriptorTable(1, self.gctx.copyDescriptorsToGpuHeap(1, equirect_texture.view));
            self.drawToCubeTexture(mesh, env_texture.resource, 0);
            self.mipgen_rgba16f.generateMipmaps(&self.gctx, env_texture.resource);
            self.gctx.addTransitionBarrier(env_texture.resource, .{ .PIXEL_SHADER_RESOURCE = true });
            self.gctx.flushResourceBarriers();
        }
        zpix.endEvent(self.gctx.cmdlist);

        //
        // Generate irradiance (cube) texture content.
        //
        zpix.beginEvent(self.gctx.cmdlist, "Generate Irradiance Cubemap");
        {
            const pipeline_info = self.getPipeline(IdLocal.init("generate_irradiance_texture"));
            self.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);
            self.gctx.cmdlist.SetGraphicsRootDescriptorTable(1, self.gctx.copyDescriptorsToGpuHeap(1, env_texture.view));
            self.drawToCubeTexture(mesh, irradiance_texture.resource, 0);
            self.mipgen_rgba16f.generateMipmaps(&self.gctx, irradiance_texture.resource);
            self.gctx.addTransitionBarrier(irradiance_texture.resource, .{ .PIXEL_SHADER_RESOURCE = true });
            self.gctx.flushResourceBarriers();
        }
        zpix.endEvent(self.gctx.cmdlist);

        //
        // Generate prefiltered env. (cube) texture content.
        //
        zpix.beginEvent(self.gctx.cmdlist, "Generate Pre-Filtered Cubemap");
        {
            const pipeline_info = self.getPipeline(IdLocal.init("generate_prefiltered_env_texture"));
            self.gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);
            self.gctx.cmdlist.SetGraphicsRootDescriptorTable(2, self.gctx.copyDescriptorsToGpuHeap(1, env_texture.view));
            {
                var mip_level: u32 = 0;
                while (mip_level < prefiltered_env_texture_num_mip_levels) : (mip_level += 1) {
                    const roughness = @as(f32, @floatFromInt(mip_level)) /
                        @as(f32, @floatFromInt(prefiltered_env_texture_num_mip_levels - 1));
                    self.gctx.cmdlist.SetGraphicsRoot32BitConstant(1, @as(u32, @bitCast(roughness)), 0);
                    self.drawToCubeTexture(mesh, prefiltered_env_texture.resource, mip_level);
                }
            }
            self.gctx.addTransitionBarrier(prefiltered_env_texture.resource, .{ .PIXEL_SHADER_RESOURCE = true });
            self.gctx.flushResourceBarriers();
        }
        zpix.endEvent(self.gctx.cmdlist);

        self.gctx.endFrame();
        self.gctx.finishGpuCommands();

        self.env_texture = env_texture;
        self.irradiance_texture = irradiance_texture;
        self.prefiltered_env_texture = prefiltered_env_texture;
    }

    fn drawToCubeTexture(
        self: *D3D12State,
        cube_mesh: Mesh,
        dest_texture: zd3d12.ResourceHandle,
        dest_mip_level: u32,
    ) void {
        const desc = self.gctx.getResourceDesc(dest_texture);
        assert(dest_mip_level < desc.MipLevels);
        const texture_width = @as(u32, @intCast(desc.Width)) >> @as(u5, @intCast(dest_mip_level));
        const texture_height = desc.Height >> @as(u5, @intCast(dest_mip_level));
        assert(texture_width == texture_height);

        self.gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @as(f32, @floatFromInt(texture_width)),
            .Height = @as(f32, @floatFromInt(texture_height)),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        }});
        self.gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
            .left = 0,
            .top = 0,
            .right = @as(c_long, @intCast(texture_width)),
            .bottom = @as(c_long, @intCast(texture_height)),
        }});
        self.gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);

        const zero = zm.Vec{ 0.0, 0.0, 0.0, 0.0 };
        const object_to_view = [_]zm.Mat{
            zm.lookToLh(zero, zm.Vec{ 1.0, 0.0, 0.0, 0.0 }, zm.Vec{ 0.0, 1.0, 0.0, 0.0 }),
            zm.lookToLh(zero, zm.Vec{ -1.0, 0.0, 0.0, 0.0 }, zm.Vec{ 0.0, 1.0, 0.0, 0.0 }),
            zm.lookToLh(zero, zm.Vec{ 0.0, 1.0, 0.0, 0.0 }, zm.Vec{ 0.0, 0.0, -1.0, 0.0 }),
            zm.lookToLh(zero, zm.Vec{ 0.0, -1.0, 0.0, 0.0 }, zm.Vec{ 0.0, 0.0, 1.0, 0.0 }),
            zm.lookToLh(zero, zm.Vec{ 0.0, 0.0, 1.0, 0.0 }, zm.Vec{ 0.0, 1.0, 0.0, 0.0 }),
            zm.lookToLh(zero, zm.Vec{ 0.0, 0.0, -1.0, 0.0 }, zm.Vec{ 0.0, 1.0, 0.0, 0.0 }),
        };
        const view_to_clip = zm.perspectiveFovLh(std.math.pi * 0.5, 1.0, 0.1, 10.0);

        const vertex_buffer = self.lookupBuffer(cube_mesh.vertex_buffer);
        const mesh_lod = cube_mesh.sub_meshes[0].lods[0];

        var cube_face_idx: u32 = 0;
        while (cube_face_idx < 6) : (cube_face_idx += 1) {
            const cube_face_rtv = self.gctx.allocateTempCpuDescriptors(.RTV, 1);
            self.gctx.device.CreateRenderTargetView(
                self.gctx.lookupResource(dest_texture).?,
                &d3d12.RENDER_TARGET_VIEW_DESC{
                    .Format = .UNKNOWN,
                    .ViewDimension = .TEXTURE2DARRAY,
                    .u = .{
                        .Texture2DArray = .{
                            .MipSlice = dest_mip_level,
                            .FirstArraySlice = cube_face_idx,
                            .ArraySize = 1,
                            .PlaneSlice = 0,
                        },
                    },
                },
                cube_face_rtv,
            );

            self.gctx.addTransitionBarrier(dest_texture, .{ .RENDER_TARGET = true });
            self.gctx.flushResourceBarriers();
            self.gctx.cmdlist.OMSetRenderTargets(1, &[_]d3d12.CPU_DESCRIPTOR_HANDLE{cube_face_rtv}, w32.TRUE, null);
            self.gctx.deallocateAllTempCpuDescriptors(.RTV);

            const mem = self.gctx.allocateUploadMemory(HDRIConstBuffer, 1);
            mem.cpu_slice[0].object_to_view = zm.transpose(zm.mul(object_to_view[cube_face_idx], view_to_clip));
            mem.cpu_slice[0].vertex_buffer_index = vertex_buffer.?.persistent_descriptor.index;
            mem.cpu_slice[0].vertex_offset = @intCast(mesh_lod.vertex_offset);

            self.gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

            self.gctx.cmdlist.DrawIndexedInstanced(
                mesh_lod.index_count,
                1,
                mesh_lod.index_offset,
                @intCast(mesh_lod.vertex_offset),
                0,
            );
        }

        self.gctx.addTransitionBarrier(dest_texture, .{ .PIXEL_SHADER_RESOURCE = true });
        self.gctx.flushResourceBarriers();
    }

    // TODO(gmodarelli): Accept arguments to allow callers to ask for mipmaps
    // NOTE: DDS files come with mipmaps, but PNG files do not
    pub fn scheduleLoadTexture(self: *D3D12State, path: []const u8, textureDesc: TextureDesc, arena: std.mem.Allocator) !TextureHandle {
        const path_id = IdLocal.init(path);
        var existing_texture = self.texture_hash.get(path_id);
        if (existing_texture) |texture_handle| {
            return texture_handle;
        }

        var should_end_frame = false;
        if (!self.gctx.is_cmdlist_opened) {
            self.gctx.beginFrame();
            should_end_frame = true;
        }

        var resource = blk: {
            const ext = std.fs.path.extension(path);

            var resource: zd3d12.ResourceHandle = undefined;
            if (std.mem.eql(u8, ext, ".dds")) {
                resource = try self.gctx.createAndUploadTex2dFromDdsFile(path, arena, .{ .is_cubemap = false });
            } else {
                assert(std.mem.eql(u8, ext, ".png"));
                resource = try self.gctx.createAndUploadTex2dFromFile(path, .{});
            }

            _ = self.gctx.lookupResource(resource).?.SetName(textureDesc.name);
            break :blk resource;
        };

        const texture = blk: {
            const srv_allocation = self.gctx.allocatePersistentGpuDescriptors(1);
            self.gctx.device.CreateShaderResourceView(
                self.gctx.lookupResource(resource).?,
                null,
                srv_allocation.cpu_handle,
            );

            self.gctx.addTransitionBarrier(resource, textureDesc.state);

            const t = Texture{
                .resource_handle = resource,
                .resource = self.gctx.lookupResource(resource).?,
                .persistent_descriptor = srv_allocation,
            };

            break :blk t;
        };

        if (should_end_frame) {
            self.gctx.endFrame();
            self.gctx.finishGpuCommands();
        }

        const texture_handle = try self.texture_pool.add(.{ .obj = texture });
        self.texture_hash.put(path_id, texture_handle) catch unreachable;
        return texture_handle;
    }

    pub fn scheduleLoadTextureCubemap(self: *D3D12State, path: []const u8, textureDesc: TextureDesc, arena: std.mem.Allocator) !TextureHandle {
        const path_id = IdLocal.init(path);
        var existing_texture = self.texture_hash.get(path_id);
        if (existing_texture) |texture_handle| {
            return texture_handle;
        }

        var should_end_frame = false;
        if (!self.gctx.is_cmdlist_opened) {
            self.gctx.beginFrame();
            should_end_frame = true;
        }

        const resource = try self.gctx.createAndUploadTex2dFromDdsFile(path, arena, .{ .is_cubemap = true });
        var path_u16: [300]u16 = undefined;
        assert(path.len < path_u16.len - 1);
        const path_len = std.unicode.utf8ToUtf16Le(path_u16[0..], path) catch unreachable;
        path_u16[path_len] = 0;
        _ = self.gctx.lookupResource(resource).?.SetName(@as(w32.LPCWSTR, @ptrCast(&path_u16)));

        const resource_desc = self.gctx.lookupResource(resource).?.GetDesc();
        const texture = blk: {
            const srv_allocation = self.gctx.allocatePersistentGpuDescriptors(1);
            self.gctx.device.CreateShaderResourceView(
                self.gctx.lookupResource(resource).?,
                &d3d12.SHADER_RESOURCE_VIEW_DESC{
                    .Format = resource_desc.Format,
                    .ViewDimension = .TEXTURECUBE,
                    .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                    .u = .{
                        .TextureCube = .{
                            .MipLevels = resource_desc.MipLevels,
                            .MostDetailedMip = 0,
                            .ResourceMinLODClamp = 0.0,
                        },
                    },
                },
                srv_allocation.cpu_handle,
            );

            self.gctx.addTransitionBarrier(resource, textureDesc.state);

            const t = Texture{
                .resource = self.gctx.lookupResource(resource).?,
                .persistent_descriptor = srv_allocation,
            };

            break :blk t;
        };

        if (should_end_frame) {
            self.gctx.endFrame();
            self.gctx.finishGpuCommands();
        }

        const texture_handle = try self.texture_pool.add(.{ .obj = texture });
        self.texture_hash.put(path_id, texture_handle) catch unreachable;
        return texture_handle;
    }

    pub fn releaseAllTextures(self: *D3D12State) void {
        var live_handles = self.texture_pool.liveHandles();
        while (live_handles.next()) |handle| {
            var texture = self.lookupTexture(handle);

            if (texture) |t| {
                if (t.resource_handle) |resource_handle| {
                    self.gctx.destroyResource(resource_handle);
                    t.resource_handle = null;
                    t.resource = null;
                } else if (t.resource) |resource| {
                    _ = resource.*.Release();
                    t.resource = null;
                }
            }

            _ = self.texture_pool.removeIfLive(handle);
        }
    }

    pub fn findTextureByName(self: *D3D12State, name: [:0]const u8) ?TextureHandle {
        const name_id = IdLocal.init(name);
        var texture = self.texture_hash.get(name_id);
        if (texture) |texture_handle| {
            return texture_handle;
        }

        return null;
    }

    pub inline fn lookupTexture(self: *D3D12State, handle: TextureHandle) ?*Texture {
        if (handle.id == TextureHandle.nil.id) {
            return null;
        }

        var texture: ?*Texture = self.texture_pool.getColumnPtr(handle, .obj) catch blk: {
            std.log.debug("Failed to lookup texture with handle: {any}", .{handle});
            break :blk null;
        };

        return texture;
    }

    pub fn findMaterialByName(self: *D3D12State, name: []const u8) ?MaterialHandle {
        const material_id = IdLocal.init(name);
        var material = self.material_hash.get(material_id);
        if (material) |material_handle| {
            return material_handle;
        }

        return null;
    }

    pub inline fn lookUpMaterial(self: *D3D12State, handle: MaterialHandle) ?*fd.PBRMaterial {
        var material: ?*fd.PBRMaterial = self.material_pool.getColumnPtr(handle, .obj) catch blk: {
            std.log.debug("Failed to lookup material with handle: {any}", .{handle});
            break :blk null;
        };

        return material;
    }

    pub fn storeMaterial(self: *D3D12State, name: []const u8, material: fd.PBRMaterial) !MaterialHandle {
        const material_id = IdLocal.init(name);
        var existing_material = self.material_hash.get(material_id);
        if (existing_material) |material_handle| {
            return material_handle;
        }

        const material_handle = try self.material_pool.add(.{ .obj = material });
        self.material_hash.put(material_id, material_handle) catch unreachable;
        return material_handle;
    }

    pub fn findMeshByName(self: *D3D12State, name: []const u8) ?MeshHandle {
        const name_id = IdLocal.init(name);
        var mesh = self.mesh_hash.get(name_id);
        if (mesh) |mesh_handle| {
            return mesh_handle;
        }

        return null;
    }

    pub fn uploadMeshData(self: *D3D12State, name: []const u8, mesh: Mesh, vertices: []Vertex, indices: []IndexType) !MeshHandle {
        const name_id = IdLocal.init(name);
        var existing_mesh = self.mesh_hash.get(name_id);
        if (existing_mesh) |mesh_handle| {
            return mesh_handle;
        }

        // NOTE(gmodarelli): For now we create a vertex and an index buffer for every mesh, but in the future these
        // buffer will be backed by one big memory allocation/heap
        // Create a index buffer.
        var vertex_buffer = self.createBuffer(.{
            .size = vertices.len * @sizeOf(Vertex),
            .state = d3d12.RESOURCE_STATES.GENERIC_READ,
            .name = L("Vertex Buffer"),
            .persistent = true,
            .has_cbv = false,
            .has_srv = true,
            .has_uav = false,
        }) catch unreachable;

        // Create an index buffer.
        var index_buffer = self.createBuffer(.{
            .size = indices.len * @sizeOf(IndexType),
            .state = .{ .INDEX_BUFFER = true },
            .name = L("Index Buffer"),
            .persistent = false,
            .has_cbv = false,
            .has_srv = false,
            .has_uav = false,
        }) catch unreachable;

        var new_mesh = Mesh{
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .sub_mesh_count = mesh.sub_mesh_count,
            .sub_meshes = undefined,
            .bounding_box = undefined,
        };

        // 1. Update sub meshes' lods vertex and index offsets
        for (0..mesh.sub_mesh_count) |sub_mesh_index| {
            const sub_mesh = &mesh.sub_meshes[sub_mesh_index];
            const bounding_box = sub_mesh.bounding_box;

            new_mesh.sub_meshes[sub_mesh_index] = SubMesh{
                .lod_count = sub_mesh.lod_count,
                .lods = undefined,
                .bounding_box = .{
                    .min = [3]f32{ bounding_box.min[0], bounding_box.min[1], bounding_box.min[2] },
                    .max = [3]f32{ bounding_box.max[0], bounding_box.max[1], bounding_box.max[2] },
                },
            };

            var new_submesh = &new_mesh.sub_meshes[sub_mesh_index];
            for (0..new_submesh.lod_count) |i| {
                new_submesh.lods[i].vertex_offset = sub_mesh.lods[i].vertex_offset;
                new_submesh.lods[i].index_offset = sub_mesh.lods[i].index_offset;
                new_submesh.lods[i].vertex_count = sub_mesh.lods[i].vertex_count;
                new_submesh.lods[i].index_count = sub_mesh.lods[i].index_count;
            }
        }

        new_mesh.bounding_box.min = [3]f32{ mesh.bounding_box.min[0], mesh.bounding_box.min[1], mesh.bounding_box.min[2] };
        new_mesh.bounding_box.max = [3]f32{ mesh.bounding_box.max[0], mesh.bounding_box.max[1], mesh.bounding_box.max[2] };

        // 2. Upload vertex data to the vertex buffer
        _ = self.scheduleUploadDataToBuffer(Vertex, vertex_buffer, 0, vertices);

        // 3. Upload index data to the index buffer
        _ = self.scheduleUploadDataToBuffer(IndexType, index_buffer, 0, indices);

        // 4. Store the mesh into the mesh pool
        const mesh_handle = try self.mesh_pool.add(.{ .obj = new_mesh });

        // 5. Store the mapping between mesh name and handle
        self.mesh_hash.put(name_id, mesh_handle) catch unreachable;

        return mesh_handle;
    }

    pub fn lookupMesh(self: *D3D12State, handle: MeshHandle) ?Mesh {
        var mesh: ?Mesh = self.mesh_pool.getColumn(handle, .obj) catch blk: {
            std.log.debug("Failed to lookup mesh with handle: {any}", .{handle});
            break :blk null;
        };

        return mesh;
    }

    pub fn generateBrdfIntegrationTexture(self: *D3D12State, arena: std.mem.Allocator) !TextureHandle {
        self.gctx.beginFrame();

        var compute_desc = d3d12.COMPUTE_PIPELINE_STATE_DESC.initDefault();
        const generate_brdf_integration_texture_pso = self.gctx.createComputeShaderPipeline(
            arena,
            &compute_desc,
            "shaders/generate_brdf_integration_texture.cs.cso",
        );

        // const pipeline = self.gctx.pipeline_pool.lookupPipeline(generate_brdf_integration_texture_pso);
        // _ = pipeline.?.pso.?.SetName(L("Generate BRDF Integration Texture PSO"));

        const resource = try self.gctx.createCommittedResource(
            .DEFAULT,
            .{},
            &blk: {
                var desc = d3d12.RESOURCE_DESC.initTex2d(
                    .R16G16_FLOAT,
                    brdf_integration_texture_resolution,
                    brdf_integration_texture_resolution,
                    1, // mip levels
                );
                desc.Flags = .{ .ALLOW_UNORDERED_ACCESS = true };
                break :blk desc;
            },
            .{ .UNORDERED_ACCESS = true },
            null,
        );
        _ = self.gctx.lookupResource(resource).?.SetName(L("BRDF Integration"));

        const srv_allocation = self.gctx.allocatePersistentGpuDescriptors(1);
        self.gctx.device.CreateShaderResourceView(
            self.gctx.lookupResource(resource).?,
            null,
            srv_allocation.cpu_handle,
        );

        const texture = Texture{
            .resource_handle = resource,
            .resource = self.gctx.lookupResource(resource).?,
            .persistent_descriptor = srv_allocation,
        };

        const uav = self.gctx.allocateTempCpuDescriptors(.CBV_SRV_UAV, 1);
        self.gctx.device.CreateUnorderedAccessView(
            self.gctx.lookupResource(resource).?,
            null,
            null,
            uav,
        );

        self.gctx.setCurrentPipeline(generate_brdf_integration_texture_pso);
        self.gctx.cmdlist.SetComputeRootDescriptorTable(0, self.gctx.copyDescriptorsToGpuHeap(1, uav));
        const num_groups = @divExact(brdf_integration_texture_resolution, 8);
        self.gctx.cmdlist.Dispatch(num_groups, num_groups, 1);

        self.gctx.addTransitionBarrier(resource, .{ .PIXEL_SHADER_RESOURCE = true });
        self.gctx.flushResourceBarriers();
        self.gctx.deallocateAllTempCpuDescriptors(.CBV_SRV_UAV);

        self.gctx.endFrame();
        self.gctx.finishGpuCommands();

        self.gctx.destroyPipeline(generate_brdf_integration_texture_pso);

        return try self.texture_pool.add(.{ .obj = texture });
    }

    pub fn drawUIImage(self: *D3D12State, image: UIImage) !void {
        const texture = self.lookupTexture(image.texture);

        const image_gpu = UIImageGPU{
            .rect = [4]f32{ image.rect[0], image.rect[1], image.rect[2], image.rect[3] },
            .color = [4]f32{ image.color[0], image.color[1], image.color[2], image.color[3] },
            .texture_index = texture.?.persistent_descriptor.index,
            ._padding = [3]f32{ 42, 42, 42 },
        };
        self.ui_images.append(image_gpu) catch unreachable;
    }

    pub fn drawUILabel(self: *D3D12State, label: UILabel) !void {
        if (!self.ui_text_formats_map.contains(label.font_size)) {
            const text_format = blk: {
                var text_format: ?*dwrite.ITextFormat = null;
                hrPanicOnFail(self.gctx.d2d.?.dwrite_factory.CreateTextFormat(
                    L("Verdana"),
                    null,
                    .BOLD,
                    .NORMAL,
                    .NORMAL,
                    @floatFromInt(label.font_size),
                    L("en-us"),
                    &text_format,
                ));
                break :blk text_format.?;
            };
            hrPanicOnFail(text_format.SetTextAlignment(.LEADING));
            hrPanicOnFail(text_format.SetParagraphAlignment(.NEAR));

            self.ui_text_formats_map.put(label.font_size, text_format) catch unreachable;
        }

        var ui_label = UILabel{
            .label = undefined,
            .font_size = label.font_size,
            .color = [4]f32{ label.color[0], label.color[1], label.color[2], label.color[3] },
            .rect = label.rect,
        };
        ui_label.label = self.frame_allocator.dupe(u8, label.label) catch unreachable;

        self.ui_labels.append(ui_label) catch unreachable;
    }

    pub fn setViewMode(self: *D3D12State, view_mode: ViewMode) void {
        self.view_mode = view_mode;
    }
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !*D3D12State {
    _ = w32.CoInitializeEx(null, w32.COINIT_APARTMENTTHREADED | w32.COINIT_DISABLE_OLE1DDE);
    _ = w32.SetProcessDPIAware();

    // Check if Windows version is supported.
    var version: w32.OSVERSIONINFOW = undefined;
    _ = w32.RtlGetVersion(&version);

    var os_is_supported = false;
    if (version.dwMajorVersion > 10) {
        os_is_supported = true;
    } else if (version.dwMajorVersion == 10 and version.dwBuildNumber >= 18363) {
        os_is_supported = true;
    }

    const d3d12core_dll = w32.LoadLibraryA("D3D12Core.dll");
    if (d3d12core_dll == null) {
        os_is_supported = false;
    } else {
        _ = w32.FreeLibrary(d3d12core_dll.?);
    }

    if (!os_is_supported) {
        _ = w32.MessageBoxA(
            null,
            \\This application can't run on currently installed version of Windows.
            \\Following versions are supported:
            \\
            \\Windows 10 May 2021 (Build 19043) or newer
            \\Windows 10 October 2020 (Build 19042.789+)
            \\Windows 10 May 2020 (Build 19041.789+)
            \\Windows 10 November 2019 (Build 18363.1350+)
            \\
            \\Please update your Windows version and try again.
        ,
            "Error",
            w32.MB_OK | w32.MB_ICONERROR,
        );
        w32.ExitProcess(0);
    }

    // Change directory to where an executable is located.
    var exe_path_buffer: [1024]u8 = undefined;
    const exe_path = std.fs.selfExeDirPath(exe_path_buffer[0..]) catch "./";
    std.os.chdir(exe_path) catch {};

    // Check if 'd3d12' folder is present next to an executable.
    const local_d3d12core_dll = w32.LoadLibraryA("d3d12/D3D12Core.dll");
    if (local_d3d12core_dll == null) {
        _ = w32.MessageBoxA(
            null,
            \\Looks like 'd3d12' folder is missing. It has to be distributed together with an application.
        ,
            "Error",
            w32.MB_OK | w32.MB_ICONERROR,
        );
        w32.ExitProcess(0);
    } else {
        _ = w32.FreeLibrary(local_d3d12core_dll.?);
    }

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var state = allocator.create(D3D12State) catch unreachable;
    state.view_mode = .lit;

    state.frame_allocator_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    state.frame_allocator = state.frame_allocator_state.allocator();

    var hwnd = zglfw.native.getWin32Window(window) catch unreachable;

    state.gctx = zd3d12.GraphicsContext.init(allocator, @as(w32.HWND, @ptrCast(hwnd)));
    state.mipgen_rgba16f = zd3d12.MipmapGenerator.init(allocator, &state.gctx, .R16G16B16A16_FLOAT, "");
    state.mipgen_rgba8 = zd3d12.MipmapGenerator.init(allocator, &state.gctx, .R8G8B8A8_UNORM, "");

    // Enable vsync.
    state.gctx.present_flags = .{ .ALLOW_TEARING = false };
    state.gctx.present_interval = 1;

    state.buffer_pool = BufferPool.init(allocator);
    state.texture_pool = TexturePool.initMaxCapacity(allocator) catch unreachable;
    state.texture_hash = TextureHashMap.init(allocator);
    state.material_pool = MaterialPool.initMaxCapacity(allocator) catch unreachable;
    state.material_hash = MaterialHashMap.init(allocator);
    state.mesh_pool = MeshPool.initMaxCapacity(allocator) catch unreachable;
    state.mesh_hash = MeshHashMap.init(allocator);
    state.pipelines = PipelineHashMap.init(allocator);
    state.ui_text_formats_map = UITextFormatHashMap.init(allocator);
    state.ui_labels = std.ArrayList(UILabel).init(allocator);
    state.gpu_profiler = Profiler.init(allocator, &state.gctx) catch unreachable;
    state.stats = FrameStats.init();

    // Small resources heap
    {
        // Create a heap for small textures allocations.
        // This is mainly used for terrain's height and splat maps
        // NOTE(gmodarelli): We're currently loading up to 10880 1-channel R8_UNORM textures, so we need roughly
        // 150MB of space.
        const heap_desc = d3d12.HEAP_DESC{
            .SizeInBytes = 150 * 1024 * 1024,
            .Properties = d3d12.HEAP_PROPERTIES.initType(.DEFAULT),
            .Alignment = 0,
            .Flags = d3d12.HEAP_FLAGS.ALLOW_ONLY_NON_RT_DS_TEXTURES,
        };
        hrPanicOnFail(state.gctx.device.CreateHeap(&heap_desc, &d3d12.IID_IHeap, @as(*?*anyopaque, @ptrCast(&state.small_textures_heap))));
        state.small_textures_heap_offset = 0;
    }

    createRenderTargets(state);
    createPipelines(state, arena);
    initializeD2DResources(state);

    // Point lights buffer
    {
        state.point_lights_buffers = blk: {
            var buffers: [D3D12State.num_buffered_frames]BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const bufferDesc = BufferDesc{
                    .size = D3D12State.point_lights_count_max * @sizeOf(renderer_types.PointLightGPU),
                    .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                    .name = L("Point Lights Buffer"),
                    .persistent = true,
                    .has_cbv = false,
                    .has_srv = true,
                    .has_uav = false,
                };

                buffers[buffer_index] = state.createBuffer(bufferDesc) catch unreachable;
            }

            break :blk buffers;
        };
        state.point_lights_count = [D3D12State.num_buffered_frames]u32{ 0, 0 };
    }

    // Upload skybox mesh
    {
        var meshes_indices = std.ArrayList(IndexType).init(arena);
        var meshes_vertices = std.ArrayList(Vertex).init(arena);
        defer meshes_indices.deinit();
        defer meshes_vertices.deinit();
        const mesh = mesh_loader.loadObjMeshFromFile(allocator, "content/meshes/cube.obj", &meshes_indices, &meshes_vertices) catch unreachable;

        state.skybox_mesh = state.uploadMeshData("skybox", mesh, meshes_vertices.items, meshes_indices.items) catch unreachable;
    }

    // Upload UI quad
    {
        var quad_indices = [_]UIIndexType{ 0, 1, 2, 0, 3, 1 };

        // Create an index buffer.
        state.quad_index_buffer = state.createBuffer(.{
            .size = quad_indices.len * @sizeOf(UIIndexType),
            .state = .{ .INDEX_BUFFER = true },
            .name = L("UI Index Buffer"),
            .persistent = false,
            .has_cbv = false,
            .has_srv = false,
            .has_uav = false,
        }) catch unreachable;

        _ = state.scheduleUploadDataToBuffer(UIIndexType, state.quad_index_buffer, 0, &quad_indices);

        state.ui_image_buffers = blk: {
            var buffers: [D3D12State.num_buffered_frames]BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                const bufferDesc = BufferDesc{
                    .size = D3D12State.ui_instances_count_max * @sizeOf(UIImageGPU),
                    .state = d3d12.RESOURCE_STATES.GENERIC_READ,
                    .name = L("UI Instance Transform Buffer"),
                    .persistent = true,
                    .has_cbv = false,
                    .has_srv = true,
                    .has_uav = false,
                };

                buffers[buffer_index] = state.createBuffer(bufferDesc) catch unreachable;
            }

            break :blk buffers;
        };

        state.ui_images = std.ArrayList(UIImageGPU).init(allocator);
    }

    // Splash screen timings
    state.splash_screen_accumulated_time = 0.0;
    state.splash_screen_duration = 9.0;
    state.splash_screen_fade_out_duration = 3.0;
    state.end_screen_accumulated_time = -5.0;
    state.end_screen_fade_in_duration = 3;

    // Upload logo
    {
        const texture_path = "content/textures/ui/tides_logo.png";
        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
        state.logo_texture = state.scheduleLoadTexture(texture_path, .{ .state = .{ .PIXEL_SHADER_RESOURCE = true }, .name = texture_path_u16 }, arena) catch unreachable;
    }

    // Upload wwise logo
    {
        const texture_path = "content/textures/ui/ak_powered_by_wwise_rgb.png";
        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
        state.wwise_logo_texture = state.scheduleLoadTexture(texture_path, .{ .state = .{ .PIXEL_SHADER_RESOURCE = true }, .name = texture_path_u16 }, arena) catch unreachable;
    }

    // Upload title
    {
        const texture_path = "content/textures/ui/hill2_splash.png";
        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
        state.splash_texture = state.scheduleLoadTexture(texture_path, .{ .state = .{ .PIXEL_SHADER_RESOURCE = true }, .name = texture_path_u16 }, arena) catch unreachable;
    }

    // Upload end screen
    {
        const texture_path = "content/textures/ui/hill2_end_screen.png";
        const texture_path_u16 = @as([*:0]const u16, @ptrCast(&texture_path));
        state.end_screen_texture = state.scheduleLoadTexture(texture_path, .{ .state = .{ .PIXEL_SHADER_RESOURCE = true }, .name = texture_path_u16 }, arena) catch unreachable;
    }

    // Generate IBL textures from HDRI
    {
        state.generateIBLTextures("content/textures/env/dikhololo_night_2k.hdr", arena) catch unreachable;
    }

    // BRDF Integration
    {
        const texture_handle = state.generateBrdfIntegrationTexture(arena) catch unreachable;
        state.brdf_integration_texture = texture_handle;
    }

    return state;
}

pub fn deinit(self: *D3D12State, allocator: std.mem.Allocator) void {
    w32.CoUninitialize();

    self.gctx.finishGpuCommands();

    self.gpu_profiler.deinit();
    self.releaseAllTextures();

    self.frame_allocator_state.deinit();

    self.buffer_pool.deinit(allocator, &self.gctx);
    self.texture_pool.deinit();
    self.texture_hash.deinit();
    self.material_pool.deinit();
    self.material_hash.deinit();
    self.mesh_pool.deinit();
    self.mesh_hash.deinit();

    _ = self.small_textures_heap.Release();
    self.small_textures_heap_offset = 0;

    self.mipgen_rgba8.deinit(&self.gctx);
    self.mipgen_rgba16f.deinit(&self.gctx);

    // Destroy all pipelines
    {
        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            self.gctx.destroyPipeline(pipeline.pipeline_handle);
        }
        self.pipelines.deinit();
    }

    _ = self.stats_brush.Release();
    _ = self.stats_text_format.Release();

    var iter = self.ui_text_formats_map.keyIterator();
    while (iter.next()) |key| {
        _ = self.ui_text_formats_map.get(key.*).?.Release();
    }
    _ = self.ui_label_brush.Release();
    self.ui_text_formats_map.deinit();
    self.ui_labels.deinit();
    self.ui_images.deinit();

    self.gctx.deinit(allocator);

    self.* = undefined;
}

pub fn beginFrame(state: *D3D12State) void {
    // Update frame counter and fps stats.
    state.stats.update();

    var gctx = &state.gctx;

    // Begin DirectX 12 rendering.
    gctx.beginFrame();

    zpix.beginEvent(gctx.cmdlist, "Render Scene");

    state.gpu_frame_profiler_index = state.gpu_profiler.startProfile(state.gctx.cmdlist, "Frame");

    zpix.beginEvent(gctx.cmdlist, "GBuffer");
    gctx.addTransitionBarrier(state.gbuffer_0.?.resource_handle, .{ .RENDER_TARGET = true });
    gctx.addTransitionBarrier(state.gbuffer_1.?.resource_handle, .{ .RENDER_TARGET = true });
    gctx.addTransitionBarrier(state.gbuffer_2.?.resource_handle, .{ .RENDER_TARGET = true });
    gctx.addTransitionBarrier(state.scene_color_rt.?.resource_handle, .{ .RENDER_TARGET = true });
    gctx.addTransitionBarrier(state.depth_rt.?.resource_handle, .{ .DEPTH_WRITE = true });
    gctx.flushResourceBarriers();

    bindGBuffer(state);

    gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
        .TopLeftX = 0.0,
        .TopLeftY = 0.0,
        .Width = @floatFromInt(state.gbuffer_0.?.width),
        .Height = @floatFromInt(state.gbuffer_0.?.height),
        .MinDepth = 0.0,
        .MaxDepth = 1.0,
    }});

    gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
        .left = 0,
        .top = 0,
        .right = @as(c_long, @intCast(state.gbuffer_0.?.width)),
        .bottom = @as(c_long, @intCast(state.gbuffer_0.?.height)),
    }});
}

pub fn endFrame(state: *D3D12State, camera: *const fd.Camera, camera_position: [3]f32) void {
    var gctx = &state.gctx;

    var skybox_mesh = state.lookupMesh(state.skybox_mesh);
    if (skybox_mesh) |mesh| {
        const skybox_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "Skybox");
        zpix.beginEvent(gctx.cmdlist, "Skybox");
        {
            const pipeline_info = state.getPipeline(IdLocal.init("skybox"));
            gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

            gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
            const index_buffer = state.lookupBuffer(mesh.index_buffer);
            const index_buffer_resource = gctx.lookupResource(index_buffer.?.resource);
            gctx.cmdlist.IASetIndexBuffer(&.{
                .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
                .SizeInBytes = @as(c_uint, @intCast(index_buffer_resource.?.GetDesc().Width)),
                .Format = if (@sizeOf(IndexType) == 2) .R16_UINT else .R32_UINT,
            });

            var z_view = zm.loadMat(camera.view[0..]);
            z_view[3] = zm.f32x4(0.0, 0.0, 0.0, 1.0);
            const z_projection = zm.loadMat(camera.projection[0..]);

            {
                const mem = gctx.allocateUploadMemory(zm.Mat, 16);
                mem.cpu_slice[0] = zm.transpose(zm.mul(z_view, z_projection));

                gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
            }

            const vertex_buffer = state.lookupBuffer(mesh.vertex_buffer);

            const lod_index: u32 = 0;

            {
                const mem = gctx.allocateUploadMemory(u32, 1);
                mem.cpu_slice[0] = vertex_buffer.?.persistent_descriptor.index;
                gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
            }

            gctx.cmdlist.DrawIndexedInstanced(
                mesh.sub_meshes[0].lods[lod_index].index_count,
                1,
                mesh.sub_meshes[0].lods[lod_index].index_offset,
                @as(i32, @intCast(mesh.sub_meshes[0].lods[lod_index].vertex_offset)),
                0,
            );
        }
        zpix.endEvent(gctx.cmdlist);
        state.gpu_profiler.endProfile(gctx.cmdlist, skybox_profiler_index, gctx.frame_index);
    }

    zpix.endEvent(gctx.cmdlist); // End GBuffer event

    // const ibl_textures = state.lookupIBLTextures();
    const brdf_texture = state.lookupTexture(state.brdf_integration_texture);
    const point_lights_buffer = state.lookupBuffer(state.point_lights_buffers[gctx.frame_index]);
    const point_lights_count = state.point_lights_count[gctx.frame_index];
    const view_projection = zm.loadMat(camera.view_projection[0..]);
    const view_projection_inverted = zm.inverse(view_projection);

    if (state.view_mode == .lit) {
        // Deferred Lighting
        const deferred_lighting_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "Deferred Lighting");
        zpix.beginEvent(gctx.cmdlist, "Deferred Lighting");
        {
            gctx.addTransitionBarrier(state.gbuffer_0.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.gbuffer_1.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.gbuffer_2.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.depth_rt.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.scene_color_rt.?.resource_handle, .{ .UNORDERED_ACCESS = true });
            gctx.flushResourceBarriers();

            const pipeline_info = state.getPipeline(IdLocal.init("deferred_lighting"));
            gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

            // Upload per-scene constant data.
            {
                const mem = gctx.allocateUploadMemory(SceneUniforms, 1);
                mem.cpu_slice[0].main_light_direction = state.main_light.direction;
                mem.cpu_slice[0].main_light_color = state.main_light.color;
                mem.cpu_slice[0].main_light_intensity = state.main_light.intensity;
                mem.cpu_slice[0].point_lights_buffer_index = point_lights_buffer.?.persistent_descriptor.index;
                mem.cpu_slice[0].point_lights_count = point_lights_count;
                mem.cpu_slice[0].prefiltered_env_texture_max_lods = prefiltered_env_texture_num_mip_levels;
                mem.cpu_slice[0].env_texture_index = state.env_texture.persistent_descriptor.index;
                mem.cpu_slice[0].irradiance_texture_index = state.irradiance_texture.persistent_descriptor.index;
                mem.cpu_slice[0].prefiltered_env_texture_index = state.prefiltered_env_texture.persistent_descriptor.index;
                mem.cpu_slice[0].brdf_integration_texture_index = brdf_texture.?.persistent_descriptor.index;
                mem.cpu_slice[0].ambient_light_intensity = 0.2;
                gctx.cmdlist.SetComputeRootConstantBufferView(2, mem.gpu_base);
            }

            // Upload per-frame constant data.
            {
                const mem = gctx.allocateUploadMemory(FrameUniforms, 1);
                mem.cpu_slice[0].view_projection = zm.transpose(view_projection);
                mem.cpu_slice[0].view_projection_inverted = zm.transpose(view_projection_inverted);
                mem.cpu_slice[0].camera_position = camera_position;

                gctx.cmdlist.SetComputeRootConstantBufferView(1, mem.gpu_base);
            }

            // Upload render targets constant data.
            {
                const mem = gctx.allocateUploadMemory(RenderTargetsUniforms, 1);

                mem.cpu_slice[0].gbuffer_0_index = state.gbuffer_0.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].gbuffer_1_index = state.gbuffer_1.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].gbuffer_2_index = state.gbuffer_2.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].depth_texture_index = state.depth_rt.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].scene_color_texture_index = state.scene_color_rt.?.uav_persistent_descriptor.index;

                gctx.cmdlist.SetComputeRootConstantBufferView(0, mem.gpu_base);
            }

            const num_groups_x = @divFloor(state.scene_color_rt.?.width, 8) + 1;
            const num_groups_y = @divFloor(state.scene_color_rt.?.height, 8) + 1;
            gctx.cmdlist.Dispatch(num_groups_x, num_groups_y, 1);
        }
        zpix.endEvent(gctx.cmdlist);
        state.gpu_profiler.endProfile(gctx.cmdlist, deferred_lighting_profiler_index, gctx.frame_index);

        // Depth-Based Fog
        const depth_based_fog_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "Depth Based Fog");
        zpix.beginEvent(gctx.cmdlist, "Depth Based Fog");
        {
            gctx.addTransitionBarrier(state.post_process_rt.?.resource_handle, .{ .RENDER_TARGET = true });
            gctx.addTransitionBarrier(state.gbuffer_0.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.scene_color_rt.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.depth_rt.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.flushResourceBarriers();

            gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
                .TopLeftX = 0.0,
                .TopLeftY = 0.0,
                .Width = @floatFromInt(gctx.viewport_width),
                .Height = @floatFromInt(gctx.viewport_height),
                .MinDepth = 0.0,
                .MaxDepth = 1.0,
            }});

            gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
                .left = 0,
                .top = 0,
                .right = @as(c_long, @intCast(gctx.viewport_width)),
                .bottom = @as(c_long, @intCast(gctx.viewport_height)),
            }});

            gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
            gctx.cmdlist.OMSetRenderTargets(
                1,
                &[_]d3d12.CPU_DESCRIPTOR_HANDLE{state.post_process_rt.?.rtv_dsv_descriptor},
                w32.TRUE,
                null,
            );

            const pipeline_info = state.getPipeline(IdLocal.init("depth_based_fog"));
            gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

            // Upload per-frame constant data.
            {
                const mem = gctx.allocateUploadMemory(FrameUniforms, 1);
                mem.cpu_slice[0].view_projection = zm.transpose(view_projection);
                mem.cpu_slice[0].view_projection_inverted = zm.transpose(view_projection_inverted);
                mem.cpu_slice[0].camera_position = camera_position;

                gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
            }

            {
                const mem = gctx.allocateUploadMemory(DepthBasedFogUniforms, 1);
                mem.cpu_slice[0].fog_color = [3]f32{ 0.4, 0.4, 0.8 };
                mem.cpu_slice[0].fog_radius = 150.0;
                mem.cpu_slice[0].fog_fade_rate = 0.05;
                mem.cpu_slice[0].fog_density = 1.0;
                mem.cpu_slice[0].scene_color_texture_index = state.scene_color_rt.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].depth_texture_index = state.depth_rt.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].gbuffer_0_texture_index = state.gbuffer_0.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0]._padding = [3]f32{ 42.0, 42.0, 42.0 };
                gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
            }

            gctx.cmdlist.DrawInstanced(3, 1, 0, 0);
        }
        zpix.endEvent(gctx.cmdlist);
        state.gpu_profiler.endProfile(gctx.cmdlist, depth_based_fog_profiler_index, gctx.frame_index);

        // Bloom
        const bloom_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "Bloom");
        zpix.beginEvent(gctx.cmdlist, "Bloom");
        {
            // Downsample
            zpix.beginEvent(gctx.cmdlist, "Downsample");
            {
                const pipeline_info = state.getPipeline(IdLocal.init("downsample"));
                gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

                for (0..D3D12State.downsample_rt_count) |i| {
                    const target = state.downsample_rts[i].?;
                    const source = if (i == 0) state.post_process_rt.? else state.downsample_rts[i - 1].?;

                    gctx.addTransitionBarrier(target.resource_handle, .{ .RENDER_TARGET = true });
                    gctx.addTransitionBarrier(source.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
                    gctx.flushResourceBarriers();

                    gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
                        .TopLeftX = 0.0,
                        .TopLeftY = 0.0,
                        .Width = @floatFromInt(target.width),
                        .Height = @floatFromInt(target.height),
                        .MinDepth = 0.0,
                        .MaxDepth = 1.0,
                    }});

                    gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
                        .left = 0,
                        .top = 0,
                        .right = @as(c_long, @intCast(target.width)),
                        .bottom = @as(c_long, @intCast(target.height)),
                    }});

                    gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
                    gctx.cmdlist.OMSetRenderTargets(
                        1,
                        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{target.rtv_dsv_descriptor},
                        w32.TRUE,
                        null,
                    );

                    const mem = gctx.allocateUploadMemory(DownsampleUniforms, 1);
                    mem.cpu_slice[0].source_resolution = [2]f32{ @floatFromInt(source.width), @floatFromInt(source.height) };
                    mem.cpu_slice[0].mip_level = @intCast(i);
                    gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
                    gctx.cmdlist.SetGraphicsRootDescriptorTable(1, gctx.copyDescriptorsToGpuHeap(1, source.srv_descriptor));

                    gctx.cmdlist.DrawInstanced(3, 1, 0, 0);
                }
            }
            zpix.endEvent(gctx.cmdlist);

            // Upsample+Blur
            zpix.beginEvent(gctx.cmdlist, "Upsample and Blur");
            {
                const pipeline_info = state.getPipeline(IdLocal.init("upsample_blur"));
                gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

                var i: u32 = D3D12State.downsample_rt_count - 1;
                while (i > 0) : (i -= 1) {
                    const source = state.downsample_rts[i].?;
                    const target = state.downsample_rts[i - 1].?;

                    gctx.addTransitionBarrier(target.resource_handle, .{ .RENDER_TARGET = true });
                    gctx.addTransitionBarrier(source.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
                    gctx.flushResourceBarriers();

                    gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
                        .TopLeftX = 0.0,
                        .TopLeftY = 0.0,
                        .Width = @floatFromInt(target.width),
                        .Height = @floatFromInt(target.height),
                        .MinDepth = 0.0,
                        .MaxDepth = 1.0,
                    }});

                    gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
                        .left = 0,
                        .top = 0,
                        .right = @as(c_long, @intCast(target.width)),
                        .bottom = @as(c_long, @intCast(target.height)),
                    }});

                    gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
                    gctx.cmdlist.OMSetRenderTargets(
                        1,
                        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{target.rtv_dsv_descriptor},
                        w32.TRUE,
                        null,
                    );

                    const mem = gctx.allocateUploadMemory(UpsampleBlurUniforms, 1);
                    mem.cpu_slice[0].source_resolution = [2]f32{ @floatFromInt(source.width), @floatFromInt(source.height) };
                    mem.cpu_slice[0].sample_scale = 1.0;
                    gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
                    gctx.cmdlist.SetGraphicsRootDescriptorTable(1, gctx.copyDescriptorsToGpuHeap(1, source.srv_descriptor));

                    gctx.cmdlist.DrawInstanced(3, 1, 0, 0);
                }
            }
            zpix.endEvent(gctx.cmdlist);
        }
        zpix.endEvent(gctx.cmdlist);
        state.gpu_profiler.endProfile(gctx.cmdlist, bloom_profiler_index, gctx.frame_index);

        // Tonemapping
        const tonemapping_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "Tonemapping");
        zpix.beginEvent(gctx.cmdlist, "Tonemapping");
        {
            const back_buffer = gctx.getBackBuffer();

            gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
            gctx.addTransitionBarrier(state.post_process_rt.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.downsample_rts[0].?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.flushResourceBarriers();

            gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
                .TopLeftX = 0.0,
                .TopLeftY = 0.0,
                .Width = @floatFromInt(gctx.viewport_width),
                .Height = @floatFromInt(gctx.viewport_height),
                .MinDepth = 0.0,
                .MaxDepth = 1.0,
            }});

            gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
                .left = 0,
                .top = 0,
                .right = @as(c_long, @intCast(gctx.viewport_width)),
                .bottom = @as(c_long, @intCast(gctx.viewport_height)),
            }});

            gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
            gctx.cmdlist.OMSetRenderTargets(
                1,
                &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
                w32.TRUE,
                null,
            );

            gctx.cmdlist.ClearRenderTargetView(
                back_buffer.descriptor_handle,
                &[4]f32{ 0.0, 0.0, 0.0, 0.0 },
                0,
                null,
            );

            const pipeline_info = state.getPipeline(IdLocal.init("tonemapping"));
            gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

            const mem = gctx.allocateUploadMemory(TonemapperUniforms, 1);
            mem.cpu_slice[0].scene_color_texture_index = state.post_process_rt.?.srv_persistent_descriptor.index;
            mem.cpu_slice[0].bloom_texture_index = state.downsample_rts[0].?.srv_persistent_descriptor.index;
            gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

            gctx.cmdlist.DrawInstanced(3, 1, 0, 0);
        }
        zpix.endEvent(gctx.cmdlist);
        state.gpu_profiler.endProfile(gctx.cmdlist, tonemapping_profiler_index, gctx.frame_index);
    } else {
        // Debub Visualization
        const debug_visualization_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "Debug Visualization");
        zpix.beginEvent(gctx.cmdlist, "Debug Visualization");
        {
            const back_buffer = gctx.getBackBuffer();
            gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
            gctx.addTransitionBarrier(state.gbuffer_0.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.gbuffer_1.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.gbuffer_2.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.addTransitionBarrier(state.depth_rt.?.resource_handle, d3d12.RESOURCE_STATES.ALL_SHADER_RESOURCE);
            gctx.flushResourceBarriers();

            gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
                .TopLeftX = 0.0,
                .TopLeftY = 0.0,
                .Width = @floatFromInt(gctx.viewport_width),
                .Height = @floatFromInt(gctx.viewport_height),
                .MinDepth = 0.0,
                .MaxDepth = 1.0,
            }});

            gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
                .left = 0,
                .top = 0,
                .right = @as(c_long, @intCast(gctx.viewport_width)),
                .bottom = @as(c_long, @intCast(gctx.viewport_height)),
            }});

            gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
            gctx.cmdlist.OMSetRenderTargets(
                1,
                &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
                w32.TRUE,
                null,
            );

            gctx.cmdlist.ClearRenderTargetView(
                back_buffer.descriptor_handle,
                &[4]f32{ 0.0, 0.0, 0.0, 0.0 },
                0,
                null,
            );

            const pipeline_info = state.getPipeline(IdLocal.init("debug_visualization"));
            gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

            // Upload per-scene constant data.
            {
                const mem = gctx.allocateUploadMemory(SceneUniforms, 1);
                mem.cpu_slice[0].main_light_direction = state.main_light.direction;
                mem.cpu_slice[0].main_light_color = state.main_light.color;
                mem.cpu_slice[0].main_light_intensity = state.main_light.intensity;
                mem.cpu_slice[0].point_lights_buffer_index = point_lights_buffer.?.persistent_descriptor.index;
                mem.cpu_slice[0].point_lights_count = point_lights_count;
                mem.cpu_slice[0].prefiltered_env_texture_max_lods = prefiltered_env_texture_num_mip_levels;
                mem.cpu_slice[0].env_texture_index = state.env_texture.persistent_descriptor.index;
                mem.cpu_slice[0].irradiance_texture_index = state.irradiance_texture.persistent_descriptor.index;
                mem.cpu_slice[0].prefiltered_env_texture_index = state.prefiltered_env_texture.persistent_descriptor.index;
                mem.cpu_slice[0].brdf_integration_texture_index = brdf_texture.?.persistent_descriptor.index;
                mem.cpu_slice[0].ambient_light_intensity = 0.2;
                gctx.cmdlist.SetGraphicsRootConstantBufferView(2, mem.gpu_base);
            }

            // Upload per-frame constant data.
            {
                const mem = gctx.allocateUploadMemory(FrameUniforms, 1);
                mem.cpu_slice[0].view_projection = zm.transpose(view_projection);
                mem.cpu_slice[0].view_projection_inverted = zm.transpose(view_projection_inverted);
                mem.cpu_slice[0].camera_position = camera_position;

                gctx.cmdlist.SetGraphicsRootConstantBufferView(1, mem.gpu_base);
            }

            // Upload render targets constant data.
            {
                const mem = gctx.allocateUploadMemory(RenderTargetsUniforms, 1);

                mem.cpu_slice[0].gbuffer_0_index = state.gbuffer_0.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].gbuffer_1_index = state.gbuffer_1.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].gbuffer_2_index = state.gbuffer_2.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].depth_texture_index = state.depth_rt.?.srv_persistent_descriptor.index;
                mem.cpu_slice[0].scene_color_texture_index = state.scene_color_rt.?.uav_persistent_descriptor.index;

                gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);
            }

            // Upload draw constant data
            {
                const mem = gctx.allocateUploadMemory(ViewModeUniforms, 1);

                mem.cpu_slice[0].view_mode = @intFromEnum(state.view_mode);
                gctx.cmdlist.SetGraphicsRootConstantBufferView(3, mem.gpu_base);
            }

            gctx.cmdlist.DrawInstanced(3, 1, 0, 0);
        }
        zpix.endEvent(gctx.cmdlist);
        state.gpu_profiler.endProfile(gctx.cmdlist, debug_visualization_profiler_index, gctx.frame_index);
    }

    // UI
    const ui_profiler_index = state.gpu_profiler.startProfile(gctx.cmdlist, "UI");
    zpix.beginEvent(gctx.cmdlist, "UI");
    {
        const screen_size_x: f32 = @as(f32, @floatFromInt(gctx.viewport_width));
        const screen_size_y: f32 = @as(f32, @floatFromInt(gctx.viewport_height));
        const screen_center_x: f32 = screen_size_x / 2;
        const screen_center_y: f32 = screen_size_y / 2;

        // Watermark Logo
        {
            const logo_size: f32 = 100;
            const top = 20.0;
            const bottom = 20.0 + logo_size;
            const left = @as(f32, @floatFromInt(gctx.viewport_width)) - 20.0 - logo_size;
            const right = @as(f32, @floatFromInt(gctx.viewport_width)) - 20.0;

            const image = UIImage{
                .rect = [4]f32{ top, bottom, left, right },
                .color = [4]f32{ 1.0, 1.0, 1.0, 1.0 },
                .texture = state.logo_texture,
            };

            state.drawUIImage(image) catch unreachable;
        }

        // Build
        {
            const build_date = @import("build_options").build_date;
            var ui_label = UILabel{
                .label = undefined,
                .font_size = 10,
                .color = [4]f32{ 0.75, 0.75, 0.6, 0.8 },
                .rect = .{ .left = 10, .top = screen_size_y, .bottom = screen_size_y - 20, .right = 500 },
            };
            var buffer = [_]u8{0} ** 128;
            ui_label.label = std.fmt.bufPrint(buffer[0..], "Tides of Revival Build: {s}", .{build_date}) catch unreachable;
            state.drawUILabel(ui_label) catch unreachable;
        }

        // Splash screen
        if (state.splash_screen_accumulated_time < state.splash_screen_duration) {
            state.splash_screen_accumulated_time += state.stats.delta_time;
            const fade_out_time = std.math.clamp(state.splash_screen_duration - state.splash_screen_accumulated_time, 0.0, state.splash_screen_fade_out_duration);
            const opacity = fade_out_time / state.splash_screen_fade_out_duration;

            const logo_size: f32 = 840;
            const logo_half_size: f32 = logo_size / 2;
            const offset_y = screen_size_y * 0.1;
            {
                // Logo
                const top = screen_center_y - logo_half_size - offset_y;
                const bottom = screen_center_y + logo_half_size - offset_y;
                const left = screen_center_x - logo_half_size;
                const right = screen_center_x + logo_half_size;

                const image = UIImage{
                    .rect = [4]f32{ top, bottom, left, right },
                    .color = [4]f32{ 1.0, 1.0, 1.0, opacity },
                    .texture = state.logo_texture,
                };

                state.drawUIImage(image) catch unreachable;
            }
            {
                // Title
                const scale_time = std.math.clamp(state.splash_screen_accumulated_time, 0.0, 3);
                const scale = tides_math.easeInOutQuad(scale_time / 3);
                const img_size_x: f32 = 768 * scale;
                const img_size_y: f32 = 192 * scale;

                const top = screen_center_y + logo_half_size - offset_y * 1.5;
                const bottom = top + img_size_y;
                const left = screen_center_x - img_size_x / 2;
                const right = screen_center_x + img_size_x / 2;

                const image = UIImage{
                    .rect = [4]f32{ top, bottom, left, right },
                    .color = [4]f32{ 1.0, 1.0, 1.0, opacity * opacity * opacity },
                    .texture = state.splash_texture,
                };

                state.drawUIImage(image) catch unreachable;
            }
            {
                // Wwise
                const img_size: f32 = 340;

                const top = screen_size_y - img_size;
                const bottom = top + img_size;
                const left = screen_size_x - img_size;
                const right = left + img_size;

                const image = UIImage{
                    .rect = [4]f32{ top, bottom, left, right },
                    .color = [4]f32{ 1.0, 1.0, 1.0, opacity },
                    .texture = state.wwise_logo_texture,
                };

                state.drawUIImage(image) catch unreachable;

                var ui_label = UILabel{
                    .label = undefined,
                    .font_size = 10,
                    .color = [4]f32{ 0.75, 0.75, 0.0, 0.75 * opacity },
                    .rect = .{ .left = 3 * screen_size_x / 4 + 50, .top = screen_size_y, .bottom = screen_size_y - 20, .right = screen_size_x },
                };
                var buffer = [_]u8{0} ** 128;
                ui_label.label = std.fmt.bufPrint(buffer[0..], "Powered by Wwise © 2006 - 2023 Audiokinetic Inc. All rights reserved.", .{}) catch unreachable;
                state.drawUILabel(ui_label) catch unreachable;
            }
        }

        // End screen
        // temp
        if (state.end_screen_accumulated_time >= 0) {
            state.end_screen_accumulated_time += state.stats.delta_time;
            // state.end_screen_accumulated_time += state.stats.delta_time;
            const fade_in_time = std.math.clamp(state.end_screen_fade_in_duration - state.end_screen_accumulated_time, 0.0, state.end_screen_fade_in_duration);
            const opacity = 1 - fade_in_time / state.end_screen_fade_in_duration;

            {
                const logo_size: f32 = 840;
                const logo_half_size: f32 = logo_size / 2;

                const top = screen_center_y - logo_half_size;
                const bottom = screen_center_y + logo_half_size;
                const left = screen_center_x - logo_half_size;
                const right = screen_center_x + logo_half_size;

                const image = UIImage{
                    .rect = [4]f32{ top, bottom, left, right },
                    .color = [4]f32{ 1.0, 1.0, 1.0, opacity },
                    .texture = state.end_screen_texture,
                };

                state.drawUIImage(image) catch unreachable;
            }
        }

        const back_buffer = gctx.getBackBuffer();

        gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
        gctx.flushResourceBarriers();

        gctx.cmdlist.RSSetViewports(1, &[_]d3d12.VIEWPORT{.{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width = @floatFromInt(gctx.viewport_width),
            .Height = @floatFromInt(gctx.viewport_height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        }});

        gctx.cmdlist.RSSetScissorRects(1, &[_]d3d12.RECT{.{
            .left = 0,
            .top = 0,
            .right = @as(c_long, @intCast(gctx.viewport_width)),
            .bottom = @as(c_long, @intCast(gctx.viewport_height)),
        }});
        gctx.cmdlist.OMSetRenderTargets(
            1,
            &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
            w32.TRUE,
            null,
        );

        const pipeline_info = state.getPipeline(IdLocal.init("ui"));
        gctx.setCurrentPipeline(pipeline_info.?.pipeline_handle);

        gctx.cmdlist.IASetPrimitiveTopology(.TRIANGLELIST);
        const index_buffer = state.lookupBuffer(state.quad_index_buffer);
        const index_buffer_resource = gctx.lookupResource(index_buffer.?.resource);
        gctx.cmdlist.IASetIndexBuffer(&.{
            .BufferLocation = index_buffer_resource.?.GetGPUVirtualAddress(),
            .SizeInBytes = @as(c_uint, @intCast(index_buffer_resource.?.GetDesc().Width)),
            .Format = if (@sizeOf(UIIndexType) == 2) .R16_UINT else .R32_UINT,
        });

        _ = state.uploadDataToBuffer(UIImageGPU, state.ui_image_buffers[gctx.frame_index], 0, state.ui_images.items);
        const ui_image_buffer = state.lookupBuffer(state.ui_image_buffers[gctx.frame_index]);

        var z_screen_to_clip = zm.identity();
        z_screen_to_clip[0] = zm.f32x4(2.0 / @as(f32, @floatFromInt(gctx.viewport_width)), 0.0, 0.0, 0.0);
        z_screen_to_clip[1] = zm.f32x4(0.0, 2.0 / -@as(f32, @floatFromInt(gctx.viewport_height)), 0.0, 0.0);
        z_screen_to_clip[2] = zm.f32x4(0.0, 0.0, 0.5, 0.0);
        z_screen_to_clip[3] = zm.f32x4(-1.0, 1.0, 0.5, 1.0);
        const mem = gctx.allocateUploadMemory(UIUniforms, 1);
        mem.cpu_slice[0].screen_to_clip = z_screen_to_clip;
        mem.cpu_slice[0].ui_transform_buffer_index = ui_image_buffer.?.persistent_descriptor.index;
        gctx.cmdlist.SetGraphicsRootConstantBufferView(0, mem.gpu_base);

        gctx.cmdlist.DrawIndexedInstanced(6, @as(u32, @intCast(state.ui_images.items.len)), 0, 0, 0);

        state.ui_images.clearRetainingCapacity();
    }
    zpix.endEvent(gctx.cmdlist);
    state.gpu_profiler.endProfile(gctx.cmdlist, ui_profiler_index, gctx.frame_index);

    zpix.endEvent(gctx.cmdlist); // Event: Render Scene
    state.gpu_profiler.endProfile(gctx.cmdlist, state.gpu_frame_profiler_index, gctx.frame_index);
    state.gpu_profiler.endFrame(gctx.cmdqueue, gctx.frame_index);

    // D2D Text Rendering
    {
        const back_buffer = gctx.getBackBuffer();
        gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
        gctx.flushResourceBarriers();

        gctx.cmdlist.OMSetRenderTargets(
            1,
            &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
            w32.TRUE,
            null,
        );

        gctx.beginDraw2d();
        {
            // Draw UI Labels
            {
                for (state.ui_labels.items) |label| {
                    if (state.ui_text_formats_map.get(label.font_size)) |text_format| {
                        state.ui_label_brush.SetColor(&.{ .r = label.color[0], .g = label.color[1], .b = label.color[2], .a = label.color[3] });

                        drawText(
                            gctx.d2d.?.context,
                            label.label,
                            text_format,
                            &d2d1.RECT_F{
                                .left = label.rect.left,
                                .top = label.rect.top,
                                .right = label.rect.right,
                                .bottom = label.rect.bottom,
                            },
                            @as(*d2d1.IBrush, @ptrCast(state.ui_label_brush)),
                        );
                    }
                }
            }

            // Rendering Stats
            {
                const stats = &state.stats;

                // FPS and CPU timings
                {
                    state.stats_brush.SetColor(&.{ .r = 0.0, .g = 1.0, .b = 0.0, .a = 1.0 });
                    if (stats.fps < 60.0) {
                        state.stats_brush.SetColor(&.{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 });
                    } else if (stats.fps < 30) {
                        state.stats_brush.SetColor(&.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 });
                    }

                    var buffer = [_]u8{0} ** 128;
                    const text = std.fmt.bufPrint(
                        buffer[0..],
                        "FPS: {d:.1}\nCPU: {d:.3} ms\nView Mode: {}",
                        .{ stats.fps, stats.average_cpu_time, state.view_mode },
                    ) catch unreachable;

                    drawText(
                        gctx.d2d.?.context,
                        text,
                        state.stats_text_format,
                        &d2d1.RECT_F{
                            .left = 10.0,
                            .top = 10.0,
                            .right = @as(f32, @floatFromInt(gctx.viewport_width)),
                            .bottom = @as(f32, @floatFromInt(gctx.viewport_height)),
                        },
                        @as(*d2d1.IBrush, @ptrCast(state.stats_brush)),
                    );
                }

                // GPU timings
                if (false) {
                    var i: u32 = 0;
                    var line_height: f32 = 14.0;
                    var vertical_offset: f32 = 36.0;
                    while (i < state.gpu_profiler.num_profiles) : (i += 1) {
                        var frame_profile_data = state.gpu_profiler.profiles.items[i];
                        var buffer = [_]u8{0} ** 64;
                        const text = std.fmt.bufPrint(
                            buffer[0..],
                            "{s}: {d:.3} ms",
                            .{ frame_profile_data.name, frame_profile_data.avg_time },
                        ) catch unreachable;

                        drawText(
                            gctx.d2d.?.context,
                            text,
                            state.stats_text_format,
                            &d2d1.RECT_F{
                                .left = 0.0,
                                .top = @as(f32, @floatFromInt(i)) * line_height + vertical_offset,
                                .right = @as(f32, @floatFromInt(gctx.viewport_width)),
                                .bottom = @as(f32, @floatFromInt(gctx.viewport_height)),
                            },
                            @as(*d2d1.IBrush, @ptrCast(state.stats_brush)),
                        );
                    }

                    // GPU Memory
                    // Collect memory usage stats
                    var video_memory_info: dxgi.QUERY_VIDEO_MEMORY_INFO = undefined;
                    hrPanicOnFail(gctx.adapter.QueryVideoMemoryInfo(0, .LOCAL, &video_memory_info));
                    {
                        var buffer = [_]u8{0} ** 256;
                        const text = std.fmt.bufPrint(
                            buffer[0..],
                            "GPU Memory: {d}/{d} MB",
                            .{ @divTrunc(video_memory_info.CurrentUsage, 1024 * 1024), @divTrunc(video_memory_info.Budget, 1024 * 1024) },
                        ) catch unreachable;

                        drawText(
                            gctx.d2d.?.context,
                            text,
                            state.stats_text_format,
                            &d2d1.RECT_F{
                                .left = 0.0,
                                .top = @as(f32, @floatFromInt(i)) * line_height + vertical_offset,
                                .right = @as(f32, @floatFromInt(gctx.viewport_width)),
                                .bottom = @as(f32, @floatFromInt(gctx.viewport_height)),
                            },
                            @as(*d2d1.IBrush, @ptrCast(state.stats_brush)),
                        );
                    }
                }
            }
        }
        // End Direct2D rendering and transition back buffer to 'present' state.
        gctx.endDraw2d();
        state.ui_labels.clearRetainingCapacity();
        _ = state.frame_allocator_state.reset(.retain_capacity);
    }

    // Prepare the back buffer to be presented to the screen
    {
        const back_buffer = gctx.getBackBuffer();
        gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATES.PRESENT);
        gctx.flushResourceBarriers();
    }

    // Call 'Present' and prepare for the next frame.
    gctx.endFrame();
}

pub fn bindGBuffer(state: *D3D12State) void {
    var gctx = &state.gctx;
    assert(gctx.is_cmdlist_opened);

    gctx.cmdlist.OMSetRenderTargets(
        4,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{
            state.gbuffer_0.?.rtv_dsv_descriptor,
            state.gbuffer_1.?.rtv_dsv_descriptor,
            state.gbuffer_2.?.rtv_dsv_descriptor,
            state.scene_color_rt.?.rtv_dsv_descriptor,
        },
        w32.FALSE,
        &state.depth_rt.?.rtv_dsv_descriptor,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.gbuffer_0.?.rtv_dsv_descriptor,
        &state.gbuffer_0.?.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.gbuffer_1.?.rtv_dsv_descriptor,
        &state.gbuffer_1.?.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.gbuffer_2.?.rtv_dsv_descriptor,
        &state.gbuffer_2.?.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.scene_color_rt.?.rtv_dsv_descriptor,
        &state.scene_color_rt.?.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearDepthStencilView(state.depth_rt.?.rtv_dsv_descriptor, .{ .DEPTH = true }, 0.0, 0, 0, null);
}

pub fn bindBackBuffer(state: *D3D12State) void {
    var gctx = &state.gctx;
    assert(gctx.is_cmdlist_opened);

    const back_buffer = gctx.getBackBuffer();

    gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
    gctx.flushResourceBarriers();

    gctx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
        w32.TRUE,
        null,
    );
    gctx.cmdlist.ClearRenderTargetView(
        back_buffer.descriptor_handle,
        &[4]f32{ 0.0, 0.0, 0.0, 0.0 },
        0,
        null,
    );
}

pub fn bindHDRTarget(state: *D3D12State) void {
    var gctx = &state.gctx;
    assert(gctx.is_cmdlist_opened);

    gctx.addTransitionBarrier(state.scene_color_rt.resource_handle, .{ .RENDER_TARGET = true });
    gctx.flushResourceBarriers();

    gctx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{state.scene_color_rt.rtv_dsv_descriptor},
        w32.TRUE,
        null,
    );
}

fn drawText(
    devctx: *d2d1.IDeviceContext6,
    text: []const u8,
    format: *dwrite.ITextFormat,
    layout_rect: *const d2d1.RECT_F,
    brush: *d2d1.IBrush,
) void {
    var utf16: [128:0]u16 = undefined;
    assert(text.len < utf16.len);
    const len = std.unicode.utf8ToUtf16Le(utf16[0..], text) catch unreachable;
    utf16[len] = 0;
    devctx.DrawText(
        &utf16,
        @as(u32, @intCast(len)),
        format,
        layout_rect,
        brush,
        d2d1.DRAW_TEXT_OPTIONS_NONE,
        .NATURAL,
    );
}

pub const RenderTarget = struct {
    resource_handle: zd3d12.ResourceHandle,
    rtv_dsv_descriptor: d3d12.CPU_DESCRIPTOR_HANDLE,
    srv_descriptor: d3d12.CPU_DESCRIPTOR_HANDLE,
    srv_persistent_descriptor: zd3d12.PersistentDescriptor,
    uav_persistent_descriptor: zd3d12.PersistentDescriptor,
    format: dxgi.FORMAT,
    width: u32,
    height: u32,
    clear_value: d3d12.CLEAR_VALUE,
};

pub const RenderTargetDesc = struct {
    format: dxgi.FORMAT,
    width: u32,
    height: u32,
    flags: d3d12.RESOURCE_FLAGS,
    initial_state: d3d12.RESOURCE_STATES,
    clear_value: d3d12.CLEAR_VALUE,
    srv: bool,
    uav: bool,
    name: [*:0]const u16,

    pub fn initColor(format: dxgi.FORMAT, in_color: *const [4]w32.FLOAT, width: u32, height: u32, srv: bool, uav: bool, name: [*:0]const u16) RenderTargetDesc {
        var flags = d3d12.RESOURCE_FLAGS{ .ALLOW_RENDER_TARGET = true };

        if (!srv) {
            flags.DENY_SHADER_RESOURCE = true;
        }

        if (uav) {
            flags.ALLOW_UNORDERED_ACCESS = true;
        }

        return .{
            .format = format,
            .width = width,
            .height = height,
            .flags = flags,
            .initial_state = .{ .RENDER_TARGET = true }, // TODO(gmodarelli): This is not true for render targets when using compute shaders
            .clear_value = d3d12.CLEAR_VALUE.initColor(format, in_color),
            .srv = srv,
            .uav = uav,
            .name = name,
        };
    }

    pub fn initDepthStencil(format: dxgi.FORMAT, depth: w32.FLOAT, stencil: w32.UINT8, width: u32, height: u32, srv: bool, uav: bool, name: [*:0]const u16) RenderTargetDesc {
        var flags = d3d12.RESOURCE_FLAGS{ .ALLOW_DEPTH_STENCIL = true };

        if (!srv) {
            flags.DENY_SHADER_RESOURCE = true;
        }

        if (uav) {
            flags.ALLOW_UNORDERED_ACCESS = true;
        }

        return .{
            .format = format,
            .width = width,
            .height = height,
            .flags = flags,
            .initial_state = .{ .DEPTH_WRITE = true },
            .clear_value = d3d12.CLEAR_VALUE.initDepthStencil(format, depth, stencil),
            .srv = srv,
            .uav = uav,
            .name = name,
        };
    }
};

fn getDepthFormatSRV(format: dxgi.FORMAT) dxgi.FORMAT {
    if (format == .D32_FLOAT) {
        return .R32_FLOAT;
    }

    return format;
}

fn createRenderTargets(state: *D3D12State) void {
    destroyRenderTarget(&state.gctx, state.depth_rt);
    state.depth_rt = blk: {
        const desc = RenderTargetDesc.initDepthStencil(.D32_FLOAT, 0.0, 0, state.gctx.viewport_width, state.gctx.viewport_height, true, false, L("Depth"));
        break :blk createRenderTarget(&state.gctx, &desc);
    };

    destroyRenderTarget(&state.gctx, state.gbuffer_0);
    state.gbuffer_0 = blk: {
        const desc = RenderTargetDesc.initColor(.R8G8B8A8_UNORM, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, state.gctx.viewport_width, state.gctx.viewport_height, true, false, L("Albedo"));
        break :blk createRenderTarget(&state.gctx, &desc);
    };

    destroyRenderTarget(&state.gctx, state.gbuffer_1);
    state.gbuffer_1 = blk: {
        const desc = RenderTargetDesc.initColor(.R10G10B10A2_UNORM, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, state.gctx.viewport_width, state.gctx.viewport_height, true, false, L("World Normal"));
        break :blk createRenderTarget(&state.gctx, &desc);
    };

    destroyRenderTarget(&state.gctx, state.gbuffer_2);
    state.gbuffer_2 = blk: {
        const desc = RenderTargetDesc.initColor(.R8G8B8A8_UNORM, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 1.0 }, state.gctx.viewport_width, state.gctx.viewport_height, true, false, L("Material"));
        break :blk createRenderTarget(&state.gctx, &desc);
    };

    destroyRenderTarget(&state.gctx, state.scene_color_rt);
    state.scene_color_rt = blk: {
        const desc = RenderTargetDesc.initColor(.R16G16B16A16_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, state.gctx.viewport_width, state.gctx.viewport_height, true, true, L("Scene Color"));
        break :blk createRenderTarget(&state.gctx, &desc);
    };

    destroyRenderTarget(&state.gctx, state.post_process_rt);
    state.post_process_rt = blk: {
        const desc = RenderTargetDesc.initColor(.R16G16B16A16_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, state.gctx.viewport_width, state.gctx.viewport_height, true, true, L("Post Process"));
        break :blk createRenderTarget(&state.gctx, &desc);
    };

    for (0..D3D12State.downsample_rt_count) |i| {
        const divisor = std.math.pow(u32, 2, @as(u32, @intCast(i)) + 1);
        const width = @divFloor(state.gctx.viewport_width, divisor);
        const height = @divFloor(state.gctx.viewport_height, divisor);

        destroyRenderTarget(&state.gctx, state.downsample_rts[i]);
        state.downsample_rts[i] = blk: {
            const desc = RenderTargetDesc.initColor(.R16G16B16A16_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, width, height, true, false, L("Scene Color Downsampled"));
            break :blk createRenderTarget(&state.gctx, &desc);
        };
    }
}

// TODO(gmodarelli): Pass different formats in RenderTargetDesc for RTV, DST, SRV and UAV
pub fn createRenderTarget(gctx: *zd3d12.GraphicsContext, rt_desc: *const RenderTargetDesc) RenderTarget {
    const resource = gctx.createCommittedResource(
        .DEFAULT,
        .{},
        &blk: {
            var desc = d3d12.RESOURCE_DESC.initTex2d(rt_desc.format, rt_desc.width, rt_desc.height, 1);
            desc.Flags = rt_desc.flags;
            break :blk desc;
        },
        rt_desc.initial_state,
        &rt_desc.clear_value,
    ) catch |err| hrPanic(err);

    _ = gctx.lookupResource(resource).?.SetName(rt_desc.name);

    var rtv_dsv_descriptor: d3d12.CPU_DESCRIPTOR_HANDLE = undefined;
    // TODO(gmodarelli): support multiple depth formats
    if (rt_desc.format == .D32_FLOAT) {
        rtv_dsv_descriptor = gctx.allocateCpuDescriptors(.DSV, 1);
        gctx.device.CreateDepthStencilView(
            gctx.lookupResource(resource).?,
            null,
            rtv_dsv_descriptor,
        );
    } else {
        rtv_dsv_descriptor = gctx.allocateCpuDescriptors(.RTV, 1);
        gctx.device.CreateRenderTargetView(
            gctx.lookupResource(resource).?,
            &d3d12.RENDER_TARGET_VIEW_DESC{
                .Format = rt_desc.format,
                .ViewDimension = .TEXTURE2D,
                .u = .{
                    .Texture2D = .{
                        .MipSlice = 0,
                        .PlaneSlice = 0,
                    },
                },
            },
            rtv_dsv_descriptor,
        );
    }

    var srv_descriptor = gctx.allocateCpuDescriptors(.CBV_SRV_UAV, 1);
    {
        const srv_format = getDepthFormatSRV(rt_desc.format);
        gctx.device.CreateShaderResourceView(
            gctx.lookupResource(resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = srv_format,
                .ViewDimension = .TEXTURE2D,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .Texture2D = .{
                        .MostDetailedMip = 0,
                        .MipLevels = 1,
                        .PlaneSlice = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            srv_descriptor,
        );
    }

    var srv_persistent_descriptor: zd3d12.PersistentDescriptor = undefined;
    if (rt_desc.srv) {
        const srv_format = getDepthFormatSRV(rt_desc.format);

        srv_persistent_descriptor = gctx.allocatePersistentGpuDescriptors(1);
        gctx.device.CreateShaderResourceView(
            gctx.lookupResource(resource).?,
            &d3d12.SHADER_RESOURCE_VIEW_DESC{
                .Format = srv_format,
                .ViewDimension = .TEXTURE2D,
                .Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
                .u = .{
                    .Texture2D = .{
                        .MostDetailedMip = 0,
                        .MipLevels = 1,
                        .PlaneSlice = 0,
                        .ResourceMinLODClamp = 0.0,
                    },
                },
            },
            srv_persistent_descriptor.cpu_handle,
        );
    }

    var uav_persistent_descriptor: zd3d12.PersistentDescriptor = undefined;
    if (rt_desc.uav) {
        uav_persistent_descriptor = gctx.allocatePersistentGpuDescriptors(1);
        gctx.device.CreateUnorderedAccessView(
            gctx.lookupResource(resource).?,
            null,
            &d3d12.UNORDERED_ACCESS_VIEW_DESC{ .Format = rt_desc.format, .ViewDimension = .TEXTURE2D, .u = .{ .Texture2D = .{
                .MipSlice = 0,
                .PlaneSlice = 0,
            } } },
            uav_persistent_descriptor.cpu_handle,
        );
    }

    return .{
        .resource_handle = resource,
        .rtv_dsv_descriptor = rtv_dsv_descriptor,
        .srv_descriptor = srv_descriptor,
        .srv_persistent_descriptor = srv_persistent_descriptor,
        .uav_persistent_descriptor = uav_persistent_descriptor,
        .format = rt_desc.format,
        .width = rt_desc.width,
        .height = rt_desc.height,
        .clear_value = rt_desc.clear_value,
    };
}

fn destroyRenderTarget(gctx: *zd3d12.GraphicsContext, render_target: ?RenderTarget) void {
    if (render_target) |rt| {
        gctx.destroyResource(rt.resource_handle);
    }
}

fn createPipelines(state: *D3D12State, arena: std.mem.Allocator) void {
    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = state.post_process_rt.?.format;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DepthStencilState.DepthEnable = 0;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/depth_based_fog.vs.cso",
            "shaders/depth_based_fog.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Depth Based Fog"));

        state.pipelines.put(IdLocal.init("depth_based_fog"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DepthStencilState.DepthEnable = 0;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/tonemapping.vs.cso",
            "shaders/tonemapping.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Tonemapping"));

        state.pipelines.put(IdLocal.init("tonemapping"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DepthStencilState.DepthEnable = 0;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/debug_visualization.vs.cso",
            "shaders/debug_visualization.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Tonemapping"));

        state.pipelines.put(IdLocal.init("debug_visualization"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R16G16B16A16_FLOAT;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DepthStencilState.DepthEnable = 0;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/downsample.vs.cso",
            "shaders/downsample.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Downsample"));

        state.pipelines.put(IdLocal.init("downsample"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R16G16B16A16_FLOAT;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DepthStencilState.DepthEnable = 0;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.BlendState.RenderTarget[0].BlendEnable = w32.TRUE;
        pso_desc.BlendState.RenderTarget[0].SrcBlend = .ONE;
        pso_desc.BlendState.RenderTarget[0].DestBlend = .ONE;
        pso_desc.BlendState.RenderTarget[0].BlendOp = .ADD;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/upsample_blur.vs.cso",
            "shaders/upsample_blur.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Upsample Blur"));

        state.pipelines.put(IdLocal.init("upsample_blur"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = state.gbuffer_0.?.format;
        pso_desc.RTVFormats[1] = state.gbuffer_1.?.format;
        pso_desc.RTVFormats[2] = state.gbuffer_2.?.format;
        pso_desc.RTVFormats[3] = state.scene_color_rt.?.format;
        pso_desc.NumRenderTargets = 4;
        pso_desc.DSVFormat = state.depth_rt.?.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;
        pso_desc.DepthStencilState.DepthFunc = .GREATER_EQUAL;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/gbuffer_fill.vs.cso",
            "shaders/gbuffer_fill_opaque.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("GBuffer Fill Opaque"));

        state.pipelines.put(IdLocal.init("gbuffer_fill_opaque"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = state.gbuffer_0.?.format;
        pso_desc.RTVFormats[1] = state.gbuffer_1.?.format;
        pso_desc.RTVFormats[2] = state.gbuffer_2.?.format;
        pso_desc.RTVFormats[3] = state.scene_color_rt.?.format;
        pso_desc.NumRenderTargets = 4;
        pso_desc.DSVFormat = state.depth_rt.?.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;
        pso_desc.DepthStencilState.DepthFunc = .GREATER_EQUAL;
        pso_desc.RasterizerState.CullMode = .NONE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/gbuffer_fill.vs.cso",
            "shaders/gbuffer_fill_masked.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("GBuffer Fill Masked"));

        state.pipelines.put(IdLocal.init("gbuffer_fill_masked"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = state.gbuffer_0.?.format;
        pso_desc.RTVFormats[1] = state.gbuffer_1.?.format;
        pso_desc.RTVFormats[2] = state.gbuffer_2.?.format;
        pso_desc.RTVFormats[3] = state.scene_color_rt.?.format;
        pso_desc.NumRenderTargets = 4;
        pso_desc.DSVFormat = state.depth_rt.?.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;
        pso_desc.DepthStencilState.DepthFunc = .GREATER_EQUAL;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/terrain_quad_tree.vs.cso",
            "shaders/terrain_quad_tree.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Terrain Quad Tree"));

        state.pipelines.put(IdLocal.init("terrain_quad_tree"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var compute_desc = d3d12.COMPUTE_PIPELINE_STATE_DESC.initDefault();
        const pso_handle = state.gctx.createComputeShaderPipeline(
            arena,
            &compute_desc,
            "shaders/deferred_lighting.cs.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Deferred Lighting PSO"));

        state.pipelines.put(IdLocal.init("deferred_lighting"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = state.gbuffer_0.?.format;
        pso_desc.RTVFormats[1] = state.gbuffer_1.?.format;
        pso_desc.RTVFormats[2] = state.gbuffer_2.?.format;
        pso_desc.RTVFormats[3] = state.scene_color_rt.?.format;
        pso_desc.NumRenderTargets = 4;
        pso_desc.DSVFormat = state.depth_rt.?.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.RasterizerState.CullMode = .FRONT;
        pso_desc.DepthStencilState.DepthFunc = .GREATER_EQUAL;
        pso_desc.DepthStencilState.DepthWriteMask = .ALL;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/skybox.vs.cso",
            "shaders/skybox.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("Skybox"));

        state.pipelines.put(IdLocal.init("skybox"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.RasterizerState.CullMode = .NONE;
        pso_desc.DepthStencilState.DepthEnable = w32.FALSE;
        pso_desc.BlendState.RenderTarget[0].BlendEnable = w32.TRUE;
        pso_desc.BlendState.RenderTarget[0].SrcBlend = .SRC_ALPHA;
        pso_desc.BlendState.RenderTarget[0].DestBlend = .INV_SRC_ALPHA;
        pso_desc.BlendState.RenderTarget[0].BlendOp = .ADD;
        pso_desc.BlendState.RenderTarget[0].SrcBlendAlpha = .INV_SRC_ALPHA;
        pso_desc.BlendState.RenderTarget[0].DestBlendAlpha = .ZERO;
        pso_desc.BlendState.RenderTarget[0].BlendOpAlpha = .ADD;
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/ui.vs.cso",
            "shaders/ui.ps.cso",
        );

        // const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        // _ = pipeline.?.pso.?.SetName(L("UI"));

        state.pipelines.put(IdLocal.init("ui"), PipelineInfo{ .pipeline_handle = pso_handle }) catch unreachable;
    }

    {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R16G16B16A16_FLOAT;
        pso_desc.NumRenderTargets = 1;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.DepthStencilState.DepthEnable = w32.FALSE;
        pso_desc.RasterizerState.CullMode = .FRONT;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const generate_env_texture_pso = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/generate_env_texture.vs.cso",
            "shaders/generate_env_texture.ps.cso",
        );
        const generate_irradiance_texture_pso = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/generate_irradiance_texture.vs.cso",
            "shaders/generate_irradiance_texture.ps.cso",
        );
        const generate_prefiltered_env_texture_pso = state.gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/generate_prefiltered_env_texture.vs.cso",
            "shaders/generate_prefiltered_env_texture.ps.cso",
        );

        state.pipelines.put(IdLocal.init("generate_env_texture"), PipelineInfo{ .pipeline_handle = generate_env_texture_pso }) catch unreachable;
        state.pipelines.put(IdLocal.init("generate_irradiance_texture"), PipelineInfo{ .pipeline_handle = generate_irradiance_texture_pso }) catch unreachable;
        state.pipelines.put(IdLocal.init("generate_prefiltered_env_texture"), PipelineInfo{ .pipeline_handle = generate_prefiltered_env_texture_pso }) catch unreachable;
    }
}

fn initializeD2DResources(state: *D3D12State) void {
    // NOTE(gmodarelli): Using Direct2D forces DirectX11on12 which prevents
    // us from using NVIDIA Nsight to capture and profile frames.
    // TODO(gmodarelli): Add an ImGUI glfw_d3d12 backend to zig-gamedev to
    // get rid of Direct2D
    // Create Direct2D brush which will be needed to display text.
    state.stats_brush = blk: {
        var brush: ?*d2d1.ISolidColorBrush = null;
        hrPanicOnFail(state.gctx.d2d.?.context.CreateSolidColorBrush(
            &.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 0.5 },
            null,
            &brush,
        ));
        break :blk brush.?;
    };

    // Create Direct2D text format which will be needed to display text.
    state.stats_text_format = blk: {
        var text_format: ?*dwrite.ITextFormat = null;
        hrPanicOnFail(state.gctx.d2d.?.dwrite_factory.CreateTextFormat(
            L("Verdana"),
            null,
            .BOLD,
            .NORMAL,
            .NORMAL,
            12.0,
            L("en-us"),
            &text_format,
        ));
        break :blk text_format.?;
    };
    hrPanicOnFail(state.stats_text_format.SetTextAlignment(.LEADING));
    hrPanicOnFail(state.stats_text_format.SetParagraphAlignment(.NEAR));

    state.ui_label_brush = blk: {
        var brush: ?*d2d1.ISolidColorBrush = null;
        hrPanicOnFail(state.gctx.d2d.?.context.CreateSolidColorBrush(
            &.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
            null,
            &brush,
        ));
        break :blk brush.?;
    };
}