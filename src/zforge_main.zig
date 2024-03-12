const std = @import("std");
const zforge = @import("zforge");
const FileSystem = zforge.FileSystem;
const Graphics = zforge.Graphics;

const window = @import("renderer/window.zig");

pub fn main() void {
    std.log.info("Did we make it? {}", .{zforge});

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    _ = main_window;

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

    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_GPU_CONFIG, "GPUCfg");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_SHADER_BINARIES, "content/compiled_shaders");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_TEXTURES, "content");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_MESHES, "content");
    FileSystem.fsSetPathForResourceDir(FileSystem.fsGetSystemFileIO(), FileSystem.ResourceMount.RM_CONTENT, FileSystem.ResourceDirectory.RD_FONTS, "content");

    var renderer_desc: Graphics.RendererDesc = undefined;
    @memset(&renderer_desc, 0);

    var is_running = true;
    while (is_running) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            is_running = false;
        }
    }
}
