const std = @import("std");
const zforge = @import("zforge");

const FileSystem = zforge.FileSystem;
const Graphics = zforge.Graphics;
const Log = zforge.Log;
const Memory = zforge.Memory;

const window = @import("renderer/window.zig");

const RendererContext = struct {
    renderer: [*c]Graphics.Renderer = null,
    graphics_queue: [*c]Graphics.Queue = null,
};

pub fn main() void {
    std.log.info("Did we make it? {}", .{zforge});

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    _ = main_window;

    if (!Memory.initMemAlloc("Tides Renderer")) {
        std.log.err("Failed to initialize Z-Forge Memory System", .{});
        return;
    }

    var fs_desc: FileSystem.FileSystemInitDesc = undefined;
    fs_desc.pAppName = "Tides Renderer";
    fs_desc.pResourceMounts[0] = null; //@ptrFromInt(0);
    fs_desc.pResourceMounts[1] = null; //@ptrFromInt(0);
    fs_desc.pResourceMounts[2] = null; //@ptrFromInt(0);
    fs_desc.pResourceMounts[3] = null; //@ptrFromInt(0);
    if (!FileSystem.initFileSystem(&fs_desc)) {
        std.log.err("Failed to initialize Z-Forge File System", .{});
        return;
    }
    defer FileSystem.exitFileSystem();

    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_DEBUG, FileSystem.ResourceDirectory.RD_LOG, "");

    Log.init_log("Tides Renderer", Log.LogLevel.eALL);
    defer Log.exit_log();

    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_GPU_CONFIG, "GPUCfg");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_SHADER_BINARIES, "content/compiled_shaders");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_TEXTURES, "content");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_MESHES, "content");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_FONTS, "content");

    var renderer_context = RendererContext{};

    var renderer_desc = std.mem.zeroes(Graphics.RendererDesc);
    renderer_desc.mD3D11Supported = false;
    renderer_desc.mGLESSupported = false;
    renderer_desc.mShaderTarget = Graphics.ShaderTarget.SHADER_TARGET_6_6;
    renderer_desc.mDisableReloadServer = true;
    Graphics.initRenderer("Tides Renderer", &renderer_desc, &renderer_context.renderer);
    if (renderer_context.renderer == null) {
        std.log.err("Failed to initialize Z-Forge Renderer", .{});
        return;
    }
    defer Graphics.exitRenderer(renderer_context.renderer);

    var queue_desc = std.mem.zeroes(Graphics.QueueDesc);
    queue_desc.mType = Graphics.QueueType.QUEUE_TYPE_GRAPHICS;
    queue_desc.mFlag = Graphics.QueueFlag.QUEUE_FLAG_INIT_MICROPROFILE;
    Graphics.add_queue(renderer_context.renderer, &queue_desc, &renderer_context.graphics_queue);
    defer Graphics.remove_queue(renderer_context.renderer, renderer_context.graphics_queue);

    var is_running = true;
    while (is_running) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            is_running = false;
        }
    }
}
