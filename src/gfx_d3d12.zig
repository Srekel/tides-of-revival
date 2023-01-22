const std = @import("std");
const assert = std.debug.assert;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const zwin32 = @import("zwin32");
const w32 = zwin32.base;
const d2d1 = zwin32.d2d1;
const d3d12 = zwin32.d3d12;
const dwrite = zwin32.dwrite;
const hrPanic = zwin32.hrPanic;
const hrPanicOnFail = zwin32.hrPanicOnFail;
const zd3d12 = @import("zd3d12");
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

const Texture = texture_module.Texture;
const TexturePool = texture_module.TexturePool;
pub const TextureDesc = texture_module.TextureDesc;
pub const TextureHandle = texture_module.TextureHandle;

pub export const D3D12SDKVersion: u32 = 608;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
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

    depth_texture: zd3d12.ResourceHandle,
    depth_texture_dsv: d3d12.CPU_DESCRIPTOR_HANDLE,

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
        // TODO
        // _ = self.gctx.lookupResource(resource).?.SetName(textureDesc.name);

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

    pub fn destroyTexture(self: *D3D12State, handle: TextureHandle) void {
        self.texture_pool.destroyTexture(handle, &self.gctx);
    }

    pub inline fn lookupTexture(self: *D3D12State, handle: TextureHandle) ?*Texture {
        return self.texture_pool.lookupTexture(handle);
    }
};

pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !D3D12State {
    _ = w32.ole32.CoInitializeEx(
        null,
        @enumToInt(w32.COINIT_APARTMENTTHREADED) | @enumToInt(w32.COINIT_DISABLE_OLE1DDE),
    );
    _ = w32.SetProcessDPIAware();

    // Check if Windows version is supported.
    var version: w32.OSVERSIONINFOW = undefined;
    _ = w32.ntdll.RtlGetVersion(&version);

    var os_is_supported = false;
    if (version.dwMajorVersion > 10) {
        os_is_supported = true;
    } else if (version.dwMajorVersion == 10 and version.dwBuildNumber >= 18363) {
        os_is_supported = true;
    }

    const d3d12core_dll = w32.kernel32.LoadLibraryW(L("D3D12Core.dll"));
    if (d3d12core_dll == null) {
        os_is_supported = false;
    } else {
        _ = w32.kernel32.FreeLibrary(d3d12core_dll.?);
    }

    if (!os_is_supported) {
        _ = w32.user32.messageBoxA(
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
            w32.user32.MB_OK | w32.user32.MB_ICONERROR,
        ) catch 0;
        w32.kernel32.ExitProcess(0);
    }

    // Change directory to where an executable is located.
    var exe_path_buffer: [1024]u8 = undefined;
    const exe_path = std.fs.selfExeDirPath(exe_path_buffer[0..]) catch "./";
    std.os.chdir(exe_path) catch {};

    // Check if 'd3d12' folder is present next to an executable.
    const local_d3d12core_dll = w32.kernel32.LoadLibraryW(L("d3d12/D3D12Core.dll"));
    if (local_d3d12core_dll == null) {
        _ = w32.user32.messageBoxA(
            null,
            \\Looks like 'd3d12' folder is missing. It has to be distributed together with an application.
        ,
            "Error",
            w32.user32.MB_OK | w32.user32.MB_ICONERROR,
        ) catch 0;
        w32.kernel32.ExitProcess(0);
    } else {
        _ = w32.kernel32.FreeLibrary(local_d3d12core_dll.?);
    }

    var hwnd = zglfw.native.getWin32Window(window) catch unreachable;

    var gctx = zd3d12.GraphicsContext.init(allocator, hwnd);
    // Enable vsync.
    // gctx.present_flags = 0;
    // gctx.present_interval = 1;

    var buffer_pool = BufferPool.init(allocator);
    var texture_pool = TexturePool.init(allocator);

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var pipelines = PipelineHashMap.init(allocator);

    const instanced_pipeline = blk: {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        break :blk gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/instanced.vs.cso",
            "shaders/instanced.ps.cso",
        );
    };

    const terrain_quad_tree_pipeline = blk: {
        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        pso_desc.InputLayout = .{
            .pInputElementDescs = null,
            .NumElements = 0,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        break :blk gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/terrain_quad_tree.vs.cso",
            "shaders/terrain_quad_tree.ps.cso",
        );
    };

    const terrain_pipeline = blk: {
        // TODO: Replace InputAssembly with vertex fetch in shader
        const input_layout_desc = [_]d3d12.INPUT_ELEMENT_DESC{
            d3d12.INPUT_ELEMENT_DESC.init("POSITION", 0, .R32G32B32_FLOAT, 0, 0, .PER_VERTEX_DATA, 0),
            d3d12.INPUT_ELEMENT_DESC.init("_Normal", 0, .R32G32B32_FLOAT, 0, @offsetOf(Vertex, "normal"), .PER_VERTEX_DATA, 0),
        };

        var pso_desc = d3d12.GRAPHICS_PIPELINE_STATE_DESC.initDefault();
        // TODO: Replace InputAssembly with vertex fetch in shader
        pso_desc.InputLayout = .{
            .pInputElementDescs = &input_layout_desc,
            .NumElements = input_layout_desc.len,
        };
        pso_desc.RTVFormats[0] = .R8G8B8A8_UNORM;
        pso_desc.NumRenderTargets = 1;
        pso_desc.DSVFormat = .D32_FLOAT;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = 0xf;
        pso_desc.PrimitiveTopologyType = .TRIANGLE;

        break :blk gctx.createGraphicsShaderPipeline(
            arena,
            &pso_desc,
            "shaders/terrain.vs.cso",
            "shaders/terrain.ps.cso",
        );
    };

    pipelines.put(IdLocal.init("instanced"), PipelineInfo{ .pipeline_handle = instanced_pipeline }) catch unreachable;
    pipelines.put(IdLocal.init("terrain_quad_tree"), PipelineInfo{ .pipeline_handle = terrain_quad_tree_pipeline }) catch unreachable;
    pipelines.put(IdLocal.init("terrain"), PipelineInfo{ .pipeline_handle = terrain_pipeline }) catch unreachable;

    var gpu_profiler = Profiler.init(allocator, &gctx) catch unreachable;

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

    const depth_texture = gctx.createCommittedResource(
        .DEFAULT,
        .{},
        &blk: {
            var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, gctx.viewport_width, gctx.viewport_height, 1);
            desc.Flags = .{ .ALLOW_DEPTH_STENCIL = true, .DENY_SHADER_RESOURCE = true };
            break :blk desc;
        },
        .{ .DEPTH_WRITE = true },
        &d3d12.CLEAR_VALUE.initDepthStencil(.D32_FLOAT, 1.0, 0),
    ) catch |err| hrPanic(err);

    const depth_texture_dsv = gctx.allocateCpuDescriptors(.DSV, 1);
    gctx.device.CreateDepthStencilView(
        gctx.lookupResource(depth_texture).?,
        null,
        depth_texture_dsv,
    );

    return D3D12State{
        .gctx = gctx,
        .gpu_profiler = gpu_profiler,
        .stats = FrameStats.init(),
        .stats_brush = stats_brush,
        .stats_text_format = stats_text_format,
        .depth_texture = depth_texture,
        .depth_texture_dsv = depth_texture_dsv,
        .pipelines = pipelines,
        .buffer_pool = buffer_pool,
        .texture_pool = texture_pool,
    };
}

pub fn deinit(self: *D3D12State, allocator: std.mem.Allocator) void {
    w32.ole32.CoUninitialize();

    self.gctx.finishGpuCommands();
    self.gpu_profiler.deinit();

    self.buffer_pool.deinit(allocator, &self.gctx);
    self.texture_pool.deinit(allocator, &self.gctx);

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

pub fn update(state: *D3D12State) void {
    // Update frame counter and fps stats.
    state.stats.update();

    var gctx = &state.gctx;

    // Begin DirectX 12 rendering.
    gctx.beginFrame();

    state.gpu_frame_profiler_index = state.gpu_profiler.startProfile(state.gctx.cmdlist, "Frame");

    // Get current back buffer resource and transition it to 'render target' state.
    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, .{ .RENDER_TARGET = true });
    gctx.flushResourceBarriers();

    gctx.cmdlist.OMSetRenderTargets(
        1,
        &[_]d3d12.CPU_DESCRIPTOR_HANDLE{back_buffer.descriptor_handle},
        w32.TRUE,
        &state.depth_texture_dsv,
    );
    gctx.cmdlist.ClearRenderTargetView(
        back_buffer.descriptor_handle,
        &.{ 0.0, 0.0, 0.0, 1.0 },
        0,
        null,
    );
    gctx.cmdlist.ClearDepthStencilView(state.depth_texture_dsv, .{ .DEPTH = true }, 1.0, 0, 0, null);
}

pub fn draw(state: *D3D12State) void {
    var gctx = &state.gctx;

    state.gpu_profiler.endProfile(gctx.cmdlist, state.gpu_frame_profiler_index, gctx.frame_index);
    state.gpu_profiler.endFrame(gctx.cmdqueue, gctx.frame_index);

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
    }
    // End Direct2D rendering and transition back buffer to 'present' state.
    gctx.endDraw2d();

    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATES.PRESENT);
    gctx.flushResourceBarriers();

    // Call 'Present' and prepare for the next frame.
    gctx.endFrame();
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
