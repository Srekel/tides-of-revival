const std = @import("std");
const assert = std.debug.assert;
const L = std.unicode.utf8ToUtf16LeStringLiteral;
const zwin32 = @import("zwin32");
const w32 = zwin32.base;
const hrPanic = zwin32.hrPanic;
const d3d12 = zwin32.d3d12;
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

    pub fn update(self: *FrameStats, window: w32.HWND, window_name: []const u8) void {
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

            var buffer = [_]u8{0} ** 128;
            const text = std.fmt.bufPrint(
                buffer[0..],
                "FPS: {d:.1}  CPU time: {d:.3} ms | {s}",
                .{ self.fps, self.average_cpu_time, window_name },
            ) catch unreachable;
            _ = w32.SetWindowTextA(window, @ptrCast([*:0]const u8, text.ptr));
        }
        self.frame_counter += 1;
    }
};

pub const D3D12State = struct {
    gctx: zd3d12.GraphicsContext,
    stats: FrameStats,

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
    gctx.present_flags = 0;
    gctx.present_interval = 1;

    const depth_texture = gctx.createCommittedResource(
        .DEFAULT,
        d3d12.HEAP_FLAG_NONE,
        &blk: {
            var desc = d3d12.RESOURCE_DESC.initTex2d(.D32_FLOAT, gctx.viewport_width, gctx.viewport_height, 1);
            desc.Flags = d3d12.RESOURCE_FLAG_ALLOW_DEPTH_STENCIL | d3d12.RESOURCE_FLAG_DENY_SHADER_RESOURCE;
            break :blk desc;
        },
        d3d12.RESOURCE_STATE_DEPTH_WRITE,
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
        .stats = FrameStats.init(),
        .depth_texture = depth_texture,
        .depth_texture_dsv = depth_texture_dsv,
    };
}

pub fn deinit(state: *D3D12State, allocator: std.mem.Allocator) void {
    w32.ole32.CoUninitialize();

    state.gctx.finishGpuCommands();
    state.gctx.deinit(allocator);
    state.* = undefined;
}

pub fn update(state: *D3D12State) void {
    // Update frame counter and fps stats.
    state.stats.update(state.gctx.window, "EGL");

    var gctx = &state.gctx;

    // Begin DirectX 12 rendering.
    gctx.beginFrame();

    // Get current back buffer resource and transition it to 'render target' state.
    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_RENDER_TARGET);
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
    gctx.cmdlist.ClearDepthStencilView(state.depth_texture_dsv, d3d12.CLEAR_FLAG_DEPTH, 1.0, 0, 0, null);
}

pub fn draw(state: *D3D12State) void {
    var gctx = &state.gctx;

    const back_buffer = gctx.getBackBuffer();
    gctx.addTransitionBarrier(back_buffer.resource_handle, d3d12.RESOURCE_STATE_PRESENT);
    gctx.flushResourceBarriers();

    // Call 'Present' and prepare for the next frame.
    gctx.endFrame();
}