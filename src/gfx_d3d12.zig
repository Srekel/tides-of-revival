const std = @import("std");
const assert = std.debug.assert;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const zpix = @import("zpix");
const zwin32 = @import("zwin32");
const w32 = zwin32.w32;
const d2d1 = zwin32.d2d1;
const d3d12 = zwin32.d3d12;
const dxgi = zwin32.dxgi;
const dwrite = zwin32.dwrite;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const zd3d12 = @import("zd3d12");
const dds_loader = zwin32.dds_loader;
const zglfw = @import("zglfw");
const profiler_module = @import("renderer/d3d12/profiler.zig");
const IdLocal = @import("variant.zig").IdLocal;
const IdLocalContext = @import("variant.zig").IdLocalContext;
const buffer_module = @import("renderer/d3d12/buffer.zig");
const texture_module = @import("renderer/d3d12/texture.zig");

pub const Profiler = profiler_module.Profiler;
pub const ProfileData = profiler_module.ProfileData;

const Buffer = buffer_module.Buffer;
const BufferPool = buffer_module.BufferPool;
pub const BufferDesc = buffer_module.BufferDesc;
pub const BufferHandle = buffer_module.BufferHandle;

pub const Texture = texture_module.Texture;
const TexturePool = texture_module.TexturePool;
pub const TextureDesc = texture_module.TextureDesc;
pub const TextureHandle = texture_module.TextureHandle;

pub export const D3D12SDKVersion: u32 = 608;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
};

pub const RenderTarget = struct {
    resource_handle: zd3d12.ResourceHandle,
    descriptor: d3d12.CPU_DESCRIPTOR_HANDLE,
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
            .initial_state = .{ .RENDER_TARGET = true },    // TODO(gmodarelli): This is not true for render targets when using compute shaders
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
        self.time = @intToFloat(f64, now_ns) / std.time.ns_per_s;
        self.delta_time = @intToFloat(f32, now_ns - self.previous_time_ns) / std.time.ns_per_s;
        self.previous_time_ns = now_ns;

        if ((now_ns - self.fps_refresh_time_ns) >= std.time.ns_per_s) {
            const t = @intToFloat(f64, now_ns - self.fps_refresh_time_ns) / std.time.ns_per_s;
            const fps = @intToFloat(f64, self.frame_counter) / t;
            const ms = (1.0 / fps) * 1000.0;

            self.fps = @floatCast(f32, fps);
            self.average_cpu_time = @floatCast(f32, ms);
            self.fps_refresh_time_ns = now_ns;
            self.frame_counter = 0;
        }
        self.frame_counter += 1;
    }
};

pub const PipelineInfo = struct {
    pipeline_handle: zd3d12.PipelineHandle,
};

const PipelineHashMap = std.HashMap(IdLocal, PipelineInfo, IdLocalContext, 80);

pub const D3D12State = struct {
    pub const num_buffered_frames = zd3d12.GraphicsContext.max_num_buffered_frames;

    gctx: zd3d12.GraphicsContext,
    gpu_profiler: Profiler,
    gpu_frame_profiler_index: u64 = undefined,

    stats: FrameStats,
    stats_brush: *d2d1.ISolidColorBrush,
    stats_text_format: *dwrite.ITextFormat,

    depth_rt: RenderTarget,

    gbuffer_0: RenderTarget,
    gbuffer_1: RenderTarget,
    gbuffer_2: RenderTarget,

    light_diffuse_rt: RenderTarget,
    light_specular_rt: RenderTarget,
    hdr_rt: RenderTarget,

    // NOTE(gmodarelli): just a test
    radiance_texture: TextureHandle,
    irradiance_texture: TextureHandle,
    specular_texture: TextureHandle,
    brdf_integration_texture: TextureHandle,

    buffer_pool: BufferPool,
    texture_pool: TexturePool,
    pipelines: PipelineHashMap,

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
                            .NumElements = @intCast(u32, @divExact(bufferDesc.size, 4)),
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

    pub fn scheduleUploadDataToBuffer(self: *D3D12State, comptime T: type, buffer_handle: BufferHandle, buffer_offset: u64, data: []T) void {
        // TODO: Schedule the upload instead of uploading immediately
        self.gctx.beginFrame();

        self.uploadDataToBuffer(T, buffer_handle, buffer_offset, data);

        self.gctx.endFrame();
        self.gctx.finishGpuCommands();
    }

    pub fn uploadDataToBuffer(self: *D3D12State, comptime T: type, buffer_handle: BufferHandle, buffer_offset: u64, data: []T) void {
        const buffer = self.buffer_pool.lookupBuffer(buffer_handle);
        if (buffer == null)
            return;

        self.gctx.addTransitionBarrier(buffer.?.resource, .{ .COPY_DEST = true });
        self.gctx.flushResourceBarriers();

        const upload_buffer_region = self.gctx.allocateUploadBufferRegion(T, @intCast(u32, data.len));
        std.mem.copy(T, upload_buffer_region.cpu_slice[0..data.len], data[0..data.len]);

        self.gctx.cmdlist.CopyBufferRegion(
            self.gctx.lookupResource(buffer.?.resource).?,
            buffer_offset,
            upload_buffer_region.buffer,
            upload_buffer_region.buffer_offset,
            upload_buffer_region.cpu_slice.len * @sizeOf(@TypeOf(upload_buffer_region.cpu_slice[0])),
        );

        self.gctx.addTransitionBarrier(buffer.?.resource, buffer.?.state);
        self.gctx.flushResourceBarriers();
    }

    pub fn scheduleLoadTexture(self: *D3D12State, path: []const u8, textureDesc: TextureDesc) !TextureHandle {
        // TODO: Schedule the upload instead of uploading immediately
        self.gctx.beginFrame();

        const resource = self.gctx.createAndUploadTex2dFromFile(path, .{}) catch |err| hrPanic(err);
        var path_u16: [300]u16 = undefined;
        assert(path.len < path_u16.len - 1);
        const path_len = std.unicode.utf8ToUtf16Le(path_u16[0..], path) catch unreachable;
        path_u16[path_len] = 0;
        _ = self.gctx.lookupResource(resource).?.SetName(path_u16);

        const texture = blk: {
            const srv_allocation = self.gctx.allocatePersistentGpuDescriptors(1);
            self.gctx.device.CreateShaderResourceView(
                self.gctx.lookupResource(resource).?,
                null,
                srv_allocation.cpu_handle,
            );

            self.gctx.addTransitionBarrier(resource, textureDesc.state);

            const t = Texture{
                .resource = resource,
                .persistent_descriptor = srv_allocation,
            };

            break :blk t;
        };

        self.gctx.endFrame();
        self.gctx.finishGpuCommands();

        return self.texture_pool.addTexture(texture);
    }

    pub fn scheduleLoadTextureCubemap(self: *D3D12State, path: []const u8, textureDesc: TextureDesc, arena: std.mem.Allocator) !TextureHandle {
        // TODO: Schedule the upload instead of uploading immediately
        self.gctx.beginFrame();

        const resource = try self.gctx.createAndUploadTexCubeFromDdsFile(path, arena);
        var path_u16: [300]u16 = undefined;
        assert(path.len < path_u16.len - 1);
        const path_len = std.unicode.utf8ToUtf16Le(path_u16[0..], path) catch unreachable;
        path_u16[path_len] = 0;
        _ = self.gctx.lookupResource(resource).?.SetName(@ptrCast(w32.LPCWSTR, &path_u16));

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

        self.gctx.endFrame();
        self.gctx.finishGpuCommands();

        return self.texture_pool.addTexture(texture);
    }

    pub fn releaseAllTextures(self: *D3D12State) void {
        self.texture_pool.releaseAllTextures();
    }

    pub inline fn lookupTexture(self: *D3D12State, handle: TextureHandle) ?*Texture {
        return self.texture_pool.lookupTexture(handle);
    }

    pub fn lookupIBLTextures(self: *D3D12State)
    struct{ radiance: ?*Texture, irradiance: ?*Texture, specular: ?*Texture, brdf: ?*Texture} {
        return .{
            .radiance = self.texture_pool.lookupTexture(self.radiance_texture),
            .irradiance = self.texture_pool.lookupTexture(self.irradiance_texture),
            .specular = self.texture_pool.lookupTexture(self.specular_texture),
            .brdf = self.texture_pool.lookupTexture(self.brdf_integration_texture),
        };
    }


    pub fn generateBrdfIntegrationTexture(self: *D3D12State, arena: std.mem.Allocator) !TextureHandle {
        self.gctx.beginFrame();

        var compute_desc = d3d12.COMPUTE_PIPELINE_STATE_DESC.initDefault();
        const generate_brdf_integration_texture_pso = self.gctx.createComputeShaderPipeline(
            arena,
            &compute_desc,
            "shaders/generate_brdf_integration_texture.cs.cso",
        );

        const pipeline = self.gctx.pipeline_pool.lookupPipeline(generate_brdf_integration_texture_pso);
        _ = pipeline.?.pso.?.SetName(L("Generate BRDF Integration Texture PSO"));

        const brdf_integration_texture_resolution = 512;
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

        return self.texture_pool.addTexture(texture);
    }
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !D3D12State {
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

    var hwnd = zglfw.native.getWin32Window(window) catch unreachable;

    var gctx = zd3d12.GraphicsContext.init(allocator, @ptrCast(w32.HWND, hwnd));
    // Enable vsync.
    gctx.present_flags = .{ .ALLOW_TEARING = false };
    gctx.present_interval = 1;

    var buffer_pool = BufferPool.init(allocator);
    var texture_pool = TexturePool.init(allocator);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    // TODO(gmodarelli): Switch to reverse depth
    const depth_rt = blk: {
        const desc = RenderTargetDesc.initDepthStencil(.D32_FLOAT, 1.0, 0, gctx.viewport_width, gctx.viewport_height, true, false, L("Depth"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    const gbuffer_0 = blk: {
        const desc = RenderTargetDesc.initColor(.R8G8B8A8_UNORM, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, gctx.viewport_width, gctx.viewport_height, true, false, L("RT0_Albedo"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    const gbuffer_1 = blk: {
        const desc = RenderTargetDesc.initColor(.R16G16B16A16_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, gctx.viewport_width, gctx.viewport_height, true, false, L("RT1_Normal"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    const gbuffer_2 = blk: {
        const desc = RenderTargetDesc.initColor(.R8G8B8A8_UNORM, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 1.0 }, gctx.viewport_width, gctx.viewport_height, true, false, L("RT2_PBR"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    const light_diffuse_rt = blk: {
        const desc = RenderTargetDesc.initColor(.R11G11B10_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, gctx.viewport_width, gctx.viewport_height, true, true, L("Light_Diffuse_RT"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    const light_specular_rt = blk: {
        const desc = RenderTargetDesc.initColor(.R11G11B10_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, gctx.viewport_width, gctx.viewport_height, true, true, L("Light_Specular_RT"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    const hdr_rt = blk: {
        const desc = RenderTargetDesc.initColor(.R16G16B16A16_FLOAT, &[4]w32.FLOAT{ 0.0, 0.0, 0.0, 0.0 }, gctx.viewport_width, gctx.viewport_height, true, true, L("HDR_RT"));
        break :blk createRenderTarget(&gctx, &desc);
    };

    var pipelines = PipelineHashMap.init(allocator);

    const instanced_pipeline = blk: {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = gbuffer_0.format;
        pso_desc.RTVFormats[1] = gbuffer_1.format;
        pso_desc.RTVFormats[2] = gbuffer_2.format;
        pso_desc.NumRenderTargets = 3;
        pso_desc.DSVFormat = depth_rt.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/instanced.vs.cso",
            "shaders/instanced.ps.cso",
        );

        const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        _ = pipeline.?.pso.?.SetName(L("Instanced PSO"));

        break :blk pso_handle;
    };

    const terrain_quad_tree_pipeline = blk: {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = gbuffer_0.format;
        pso_desc.RTVFormats[1] = gbuffer_1.format;
        pso_desc.RTVFormats[2] = gbuffer_2.format;
        pso_desc.NumRenderTargets = 3;
        pso_desc.DSVFormat = depth_rt.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/terrain_quad_tree.vs.cso",
            "shaders/terrain_quad_tree.ps.cso",
        );

        const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        _ = pipeline.?.pso.?.SetName(L("Terrain Quad Tree PSO"));

        break :blk pso_handle;
    };

    const deferred_lighting_pso = blk: {
        var compute_desc = d3d12.COMPUTE_PIPELINE_STATE_DESC.initDefault();
        const pso_handle = gctx.createComputeShaderPipeline(
            arena,
            &compute_desc,
            "shaders/deferred_lighting.cs.cso",
        );

        const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        _ = pipeline.?.pso.?.SetName(L("Deferred Lighting PSO"));

        break :blk pso_handle;
    };

    const lighting_composition_pso = blk: {
        var compute_desc = d3d12.COMPUTE_PIPELINE_STATE_DESC.initDefault();
        const pso_handle = gctx.createComputeShaderPipeline(
            arena,
            &compute_desc,
            "shaders/lighting_composition.cs.cso",
        );

        const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        _ = pipeline.?.pso.?.SetName(L("Lighting Composition PSO"));

        break :blk pso_handle;
    };

    // TODO(gmodarelli): Which GBuffer RTs should the skybox write to?
    const sample_env_texture_pso = blk: {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = gbuffer_0.format;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = depth_rt.format;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.RasterizerState.CullMode = .FRONT;
        pso_desc.DepthStencilState.DepthFunc = .LESS_EQUAL;
        pso_desc.DepthStencilState.DepthWriteMask = .ZERO;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        const pso_handle = gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/sample_env_texture.vs.cso",
            "shaders/sample_env_texture.ps.cso",
        );

        const pipeline = gctx.pipeline_pool.lookupPipeline(pso_handle);
        _ = pipeline.?.pso.?.SetName(L("Sample Env Texture PSO"));

        break :blk pso_handle;
    };

    pipelines.put(IdLocal.init("instanced"), PipelineInfo{ .pipeline_handle = instanced_pipeline }) catch unreachable;
    pipelines.put(IdLocal.init("terrain_quad_tree"), PipelineInfo{ .pipeline_handle = terrain_quad_tree_pipeline }) catch unreachable;
    pipelines.put(IdLocal.init("deferred_lighting"), PipelineInfo{ .pipeline_handle = deferred_lighting_pso }) catch unreachable;
    pipelines.put(IdLocal.init("lighting_composition"), PipelineInfo{ .pipeline_handle = lighting_composition_pso }) catch unreachable;
    pipelines.put(IdLocal.init("sample_env_texture"), PipelineInfo{ .pipeline_handle = sample_env_texture_pso }) catch unreachable;

    var gpu_profiler = Profiler.init(allocator, &gctx) catch unreachable;

    // NOTE(gmodarelli): Using Direct2D forces DirectX11on12 which prevents
    // us from using NVIDIA Nsight to caputer and profile frames.
    // TODO(gmodarelli): Add an ImGUI glfw_d3d12 backend to zig-gamedev to
    // get rid of Direct2D
    // Create Direct2D brush which will be needed to display text.
    const stats_brush = blk: {
        var brush: ?*d2d1.ISolidColorBrush = null;
        hrPanicOnFail(gctx.d2d.?.context.CreateSolidColorBrush(
            &.{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 0.5 },
            null,
            &brush,
        ));
        break :blk brush.?;
    };

    // Create Direct2D text format which will be needed to display text.
    const stats_text_format = blk: {
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
    hrPanicOnFail(stats_text_format.SetTextAlignment(.LEADING));
    hrPanicOnFail(stats_text_format.SetParagraphAlignment(.NEAR));

    var d3d12_state = D3D12State{
        .gctx = gctx,
        .gpu_profiler = gpu_profiler,
        .stats = FrameStats.init(),
        .stats_brush = stats_brush,
        .stats_text_format = stats_text_format,
        .depth_rt = depth_rt,
        .gbuffer_0 = gbuffer_0,
        .gbuffer_1 = gbuffer_1,
        .gbuffer_2 = gbuffer_2,
        .light_diffuse_rt = light_diffuse_rt,
        .light_specular_rt = light_specular_rt,
        .hdr_rt = hdr_rt,
        .radiance_texture = undefined,
        .irradiance_texture = undefined,
        .specular_texture = undefined,
        .brdf_integration_texture = undefined,
        .pipelines = pipelines,
        .buffer_pool = buffer_pool,
        .texture_pool = texture_pool,
    };

    // Radiance
    {
        const texture_desc = TextureDesc{
            .state = d3d12.RESOURCE_STATES.GENERIC_READ,
            .name = L("Radiance"),
        };
        const path = "content/textures/env/alps_field_2k_cube_radiance.dds";
        const texture_handle = d3d12_state.scheduleLoadTextureCubemap(path, texture_desc, arena) catch unreachable;
        d3d12_state.radiance_texture = texture_handle;
    }

    // Irradiance
    {
        const texture_desc = TextureDesc{
            .state = d3d12.RESOURCE_STATES.GENERIC_READ,
            .name = L("Irradiance"),
        };
        const path = "content/textures/env/alps_field_2k_cube_irradiance.dds";
        const texture_handle = d3d12_state.scheduleLoadTextureCubemap(path, texture_desc, arena) catch unreachable;
        d3d12_state.irradiance_texture = texture_handle;
    }

    // Specular
    {
        const texture_desc = TextureDesc{
            .state = d3d12.RESOURCE_STATES.GENERIC_READ,
            .name = L("Specular"),
        };
        const path = "content/textures/env/alps_field_2k_cube_specular.dds";
        const texture_handle = d3d12_state.scheduleLoadTextureCubemap(path, texture_desc, arena) catch unreachable;
        d3d12_state.specular_texture = texture_handle;
    }

    // BRDF Integration
    {
        const texture_handle = d3d12_state.generateBrdfIntegrationTexture(arena) catch unreachable;
        d3d12_state.brdf_integration_texture = texture_handle;
    }

    return d3d12_state;
}

pub fn deinit(self: *D3D12State, allocator: std.mem.Allocator) void {
    w32.CoUninitialize();

    self.gctx.finishGpuCommands();
    self.gpu_profiler.deinit();

    self.buffer_pool.deinit(allocator, &self.gctx);
    self.texture_pool.deinit(allocator);

    // Destroy all pipelines
    {
        var it = self.pipelines.valueIterator();
        while (it.next()) |pipeline| {
            self.gctx.destroyPipeline(pipeline.pipeline_handle);
        }
        self.pipelines.deinit();
    }

    self.gctx.deinit(allocator);

    _ = self.stats_brush.Release();
    _ = self.stats_text_format.Release();
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
}

pub fn endFrame(state: *D3D12State) void {
    var gctx = &state.gctx;

    zpix.endEvent(gctx.cmdlist);
    state.gpu_profiler.endProfile(gctx.cmdlist, state.gpu_frame_profiler_index, gctx.frame_index);
    state.gpu_profiler.endFrame(gctx.cmdqueue, gctx.frame_index);

    // Get current back buffer resource and transition it to 'render target' state.
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
        &.{ 0.0, 0.0, 0.0, 0.0 },
        0,
        null,
    );

    gctx.beginDraw2d();
    {
        const stats = &state.stats;
        state.stats_brush.SetColor(&.{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });

        // FPS and CPU timings
        {
            var buffer = [_]u8{0} ** 64;
            const text = std.fmt.bufPrint(
                buffer[0..],
                "FPS: {d:.1}\nCPU: {d:.3} ms",
                .{ stats.fps, stats.average_cpu_time },
            ) catch unreachable;

            drawText(
                gctx.d2d.?.context,
                text,
                state.stats_text_format,
                &d2d1.RECT_F{
                    .left = 0.0,
                    .top = 0.0,
                    .right = @intToFloat(f32, gctx.viewport_width),
                    .bottom = @intToFloat(f32, gctx.viewport_height),
                },
                @ptrCast(*d2d1.IBrush, state.stats_brush),
            );
        }

        // GPU timings

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
                    .top = @intToFloat(f32, i) * line_height + vertical_offset,
                    .right = @intToFloat(f32, gctx.viewport_width),
                    .bottom = @intToFloat(f32, gctx.viewport_height),
                },
                @ptrCast(*d2d1.IBrush, state.stats_brush),
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
                    .top = @intToFloat(f32, i) * line_height + vertical_offset,
                    .right = @intToFloat(f32, gctx.viewport_width),
                    .bottom = @intToFloat(f32, gctx.viewport_height),
                },
                @ptrCast(*d2d1.IBrush, state.stats_brush),
            );
        }
    }
    // End Direct2D rendering and transition back buffer to 'present' state.
    gctx.endDraw2d();

    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATES.PRESENT);
    gctx.flushResourceBarriers();

    // Call 'Present' and prepare for the next frame.
    gctx.endFrame();
}

pub fn bindGBuffer(state: *D3D12State) void {
    var gctx = &state.gctx;
    assert(gctx.is_cmdlist_opened);

    gctx.cmdlist.OMSetRenderTargets(
        3,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{
            state.gbuffer_0.descriptor,
            state.gbuffer_1.descriptor,
            state.gbuffer_2.descriptor,
        },
        w32.FALSE,
        &state.depth_rt.descriptor,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.gbuffer_0.descriptor,
        &state.gbuffer_0.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.gbuffer_1.descriptor,
        &state.gbuffer_1.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearRenderTargetView(
        state.gbuffer_2.descriptor,
        &state.gbuffer_2.clear_value.u.Color,
        0,
        null,
    );

    gctx.cmdlist.ClearDepthStencilView(state.depth_rt.descriptor, .{ .DEPTH = true }, 1.0, 0, 0, null);
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
        @intCast(u32, len),
        format,
        layout_rect,
        brush,
        d2d1.DRAW_TEXT_OPTIONS_NONE,
        .NATURAL,
    );
}

fn getDepthFormatSRV(format: dxgi.FORMAT) dxgi.FORMAT {
    if (format == .D32_FLOAT) {
        return .R32_FLOAT;
    }

    return format;
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

    var descriptor: d3d12.CPU_DESCRIPTOR_HANDLE = undefined;
    // TODO(gmodarelli): support multiple depth formats
    if (rt_desc.format == .D32_FLOAT) {
        descriptor = gctx.allocateCpuDescriptors(.DSV, 1);
        gctx.device.CreateDepthStencilView(
            gctx.lookupResource(resource).?,
            null,
            descriptor,
        );
    } else {
        descriptor = gctx.allocateCpuDescriptors(.RTV, 1);
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
            descriptor,
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
            &d3d12.UNORDERED_ACCESS_VIEW_DESC{
                .Format = rt_desc.format,
                .ViewDimension = .TEXTURE2D,
                .u = .{
                    .Texture2D = .{
                        .MipSlice = 0,
                        .PlaneSlice = 0,
                    }
                }
            },
            uav_persistent_descriptor.cpu_handle,
        );
    }

    return .{
        .resource_handle = resource,
        .descriptor = descriptor,
        .srv_persistent_descriptor = srv_persistent_descriptor,
        .uav_persistent_descriptor = uav_persistent_descriptor,
        .format = rt_desc.format,
        .width = rt_desc.width,
        .height = rt_desc.height,
        .clear_value = rt_desc.clear_value,
    };
}
