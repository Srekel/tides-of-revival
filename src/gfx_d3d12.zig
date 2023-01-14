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

pub export const D3D12SDKVersion: u32 = 608;
pub export const D3D12SDKPath: [*:0]const u8 = ".\\d3d12\\";

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

pub const ProfileData = struct {
    pub const filter_size: u64 = 64;

    name: []const u8 = undefined,
    query_started: bool = false,
    query_finished: bool = false,
    active: bool = false,
    start_time: u64,
    end_time: u64,

    time_samples: [filter_size]f64 = undefined,
    current_sample: u64 = 0,
    avg_time: f64,
    max_time: f64,
};

pub const Profiler = struct {
    pub const max_profiles: u64 = 64;

    profiles: std.ArrayList(ProfileData),
    num_profiles: u64,
    query_heap: *d3d12.IQueryHeap,
    readback_buffer: *d3d12.IResource,

    pub fn init(allocator: std.mem.Allocator, gctx: *zd3d12.GraphicsContext) !Profiler {
        const query_heap = blk: {
            const query_heap_desc = d3d12.QUERY_HEAP_DESC{
                .Type = .TIMESTAMP,
                .Count = max_profiles * 2,
                .NodeMask = 0,
            };

            var query_heap: *d3d12.IQueryHeap = undefined;
            hrPanicOnFail(gctx.device.CreateQueryHeap(&query_heap_desc, &d3d12.IID_IQueryHeap, @ptrCast(*?*anyopaque, &query_heap)));
            break :blk query_heap;
        };

        const readback_buffer = blk: {
            const readback_buffer_desc = d3d12.RESOURCE_DESC.initBuffer(max_profiles * zd3d12.GraphicsContext.max_num_buffered_frames * 2 * @sizeOf(u64));
            const readback_heap_props = d3d12.HEAP_PROPERTIES.initType(.READBACK);

            var readback_buffer: *d3d12.IResource = undefined;
            hrPanicOnFail(gctx.device.CreateCommittedResource(
                &readback_heap_props,
                .{},
                &readback_buffer_desc,
                .{ .COPY_DEST = true },
                null,
                &d3d12.IID_IResource,
                @ptrCast(*?*anyopaque, &readback_buffer),
            ));
            break :blk readback_buffer;
        };

        var profiles = std.ArrayList(ProfileData).init(allocator);
        profiles.resize(max_profiles * zd3d12.GraphicsContext.max_num_buffered_frames * 2) catch unreachable;

        return Profiler{
            .profiles = profiles,
            .num_profiles = 0,
            .query_heap = query_heap,
            .readback_buffer = readback_buffer,
        };
    }

    pub fn deinit(self: *Profiler) void {
        self.profiles.deinit();
    }

    pub fn startProfile(self: *Profiler, cmdlist: *d3d12.IGraphicsCommandList6, name: []const u8) u64 {
        var profile_index: u64 = 0xffff_ffff_ffff_ffff;
        var i: u64 = 0;
        while (i < self.num_profiles) : (i += 1) {
            if (std.mem.eql(u8, name, self.profiles.items[i].name)) {
                profile_index = i;
                break;
            }
        }

        if (profile_index == 0xffff_ffff_ffff_ffff) {
            assert(self.num_profiles < Profiler.max_profiles);
            profile_index = self.num_profiles;
            self.num_profiles += 1;
            self.profiles.items[profile_index].name = name;
        }

        var profile_data = &self.profiles.items[profile_index];
        assert(profile_data.query_started == false);
        assert(profile_data.query_finished == false);
        profile_data.active = true;

        // Insert the start timestamp
        const start_query_index: u32 = @intCast(u32, profile_index * 2);
        cmdlist.EndQuery(self.query_heap, .TIMESTAMP, start_query_index);

        profile_data.query_started = true;
        profile_data.current_sample = 0;

        return profile_index;
    }

    pub fn endProfile(self: *Profiler, cmdlist: *d3d12.IGraphicsCommandList6, index: u64, current_frame_index: u32) void {
        assert(index < self.num_profiles);

        var profile_data = &self.profiles.items[index];
        assert(profile_data.query_started == true);
        assert(profile_data.query_finished == false);

        // Insert the end timestamp
        const start_query_index: u32 = @intCast(u32, index * 2);
        const end_query_index = start_query_index + 1;
        cmdlist.EndQuery(self.query_heap, .TIMESTAMP, end_query_index);

        // Resolve the data
        const dest_offset: u64 = ((current_frame_index * Profiler.max_profiles * 2) + start_query_index) * @sizeOf(u64);
        cmdlist.ResolveQueryData(self.query_heap, .TIMESTAMP, start_query_index, 2, self.readback_buffer, dest_offset);

        profile_data.query_started = false;
        profile_data.query_finished = true;
    }

    pub fn endFrame(self: *Profiler, queue: *d3d12.ICommandQueue, current_frame_index: u32) void {
        var gpu_frequency: u64 = 0;
        hrPanicOnFail(queue.GetTimestampFrequency(&gpu_frequency));

        var readback_buffer_mapping: [*]u8 = undefined;
        hrPanicOnFail(self.readback_buffer.Map(
            0,
            null,
            @ptrCast(*?*anyopaque, &readback_buffer_mapping),
        ));
        var frame_query_data = @ptrCast([*]u64, @alignCast(@alignOf(u64), readback_buffer_mapping));

        var i: u64 = 0;
        while (i < self.num_profiles) : (i += 1) {
            self.updateProfile(i, gpu_frequency, current_frame_index, frame_query_data);
        }

        self.readback_buffer.Unmap(0, null);
    }

    fn updateProfile(self: *Profiler, profile_index: u64, gpu_frequency: u64, current_frame_index: u32, frame_query_data: [*]u64) void {
        var profile = &self.profiles.items[profile_index];
        profile.query_finished = false;
        var time: f64 = 0.0;

        // Get the query data
        const start_time_index = current_frame_index * Profiler.max_profiles * 2 + profile_index * 2;
        const end_time_index = start_time_index + 1;
        const start_time = frame_query_data[start_time_index];
        const end_time = frame_query_data[end_time_index];

        if (end_time > start_time) {
            const delta: f64 = @intToFloat(f64, end_time - start_time);
            const frequency: f64 = @intToFloat(f64, gpu_frequency);
            time = (delta / frequency) * 1000.0;
        }

        profile.time_samples[profile.current_sample] = time;
        profile.current_sample = (profile.current_sample + 1) % ProfileData.filter_size;

        var max_time: f64 = 0.0;
        var avg_time: f64 = 0.0;
        var avg_time_samples: u64 = 0;
        var i: u64 = 0;
        while (i < ProfileData.filter_size) : (i += 1) {
            if (profile.time_samples[i] <= 0.0) {
                continue;
            }

            max_time = std.math.max(profile.time_samples[i], max_time);
            avg_time += profile.time_samples[i];
            avg_time_samples += 1;
        }

        if (avg_time_samples > 0) {
            avg_time /= @intToFloat(f64, avg_time_samples);
        }

        profile.avg_time = avg_time;
        profile.max_time = max_time;

        profile.active = false;
    }
};

pub const PersistentResource = struct {
    resource: zd3d12.ResourceHandle,
    persistent_descriptor: zd3d12.PersistentDescriptor,
};

pub const D3D12State = struct {
    gctx: zd3d12.GraphicsContext,
    gpu_profiler: Profiler,
    gpu_frame_profiler_index: u64 = undefined,

    stats: FrameStats,
    stats_brush: *d2d1.ISolidColorBrush,
    stats_text_format: *dwrite.ITextFormat,

    depth_texture: zd3d12.ResourceHandle,
    depth_texture_dsv: d3d12.CPU_DESCRIPTOR_HANDLE,
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

    var profiler = Profiler.init(allocator, &gctx) catch unreachable;

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
        .gpu_profiler = profiler,
        .stats = FrameStats.init(),
        .stats_brush = stats_brush,
        .stats_text_format = stats_text_format,
        .depth_texture = depth_texture,
        .depth_texture_dsv = depth_texture_dsv,
    };
}

pub fn deinit(state: *D3D12State, allocator: std.mem.Allocator) void {
    w32.ole32.CoUninitialize();

    state.gctx.finishGpuCommands();
    state.gctx.deinit(allocator);
    state.gpu_profiler.deinit();
    _ = state.stats_brush.Release();
    _ = state.stats_text_format.Release();
    state.* = undefined;
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
