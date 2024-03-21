const std = @import("std");
const zforge = @import("zforge");

const FileSystem = zforge.FileSystem;
const Graphics = zforge.Graphics;
const Log = zforge.Log;
const Memory = zforge.Memory;
const ResourceLoader = zforge.ResourceLoader;

const window = @import("renderer/window.zig");

const StaticSamplers = struct {
    bilinear_repeat: [*c]Graphics.Sampler = null,
    bilinear_clamp_to_edge: [*c]Graphics.Sampler = null,
    point_repeat: [*c]Graphics.Sampler = null,
    point_clamp_to_edge: [*c]Graphics.Sampler = null,
    point_clamp_to_border: [*c]Graphics.Sampler = null,

    pub fn init(renderer: [*c]Graphics.Renderer) StaticSamplers {
        var static_samplers = std.mem.zeroes(StaticSamplers);

        {
            var desc = std.mem.zeroes(Graphics.SamplerDesc);
            desc.mAddressU = Graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = Graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = Graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = Graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = Graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = Graphics.MipMapMode.MIPMAP_MODE_LINEAR;
            Graphics.add_sampler(renderer, &desc, &static_samplers.bilinear_repeat);
        }

        {
            var desc = std.mem.zeroes(Graphics.SamplerDesc);
            desc.mAddressU = Graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = Graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = Graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = Graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = Graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = Graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            Graphics.add_sampler(renderer, &desc, &static_samplers.point_repeat);
        }

        {
            var desc = std.mem.zeroes(Graphics.SamplerDesc);
            desc.mAddressU = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = Graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = Graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = Graphics.MipMapMode.MIPMAP_MODE_LINEAR;
            Graphics.add_sampler(renderer, &desc, &static_samplers.bilinear_clamp_to_edge);
        }

        {
            var desc = std.mem.zeroes(Graphics.SamplerDesc);
            desc.mAddressU = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = Graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = Graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = Graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            Graphics.add_sampler(renderer, &desc, &static_samplers.point_clamp_to_edge);
        }

        {
            var desc = std.mem.zeroes(Graphics.SamplerDesc);
            desc.mAddressU = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressV = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressW = Graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mMinFilter = Graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = Graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = Graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            Graphics.add_sampler(renderer, &desc, &static_samplers.point_clamp_to_border);
        }

        return static_samplers;
    }

    pub fn exit(self: *StaticSamplers, renderer: [*c]Graphics.Renderer) void {
        Graphics.remove_sampler(renderer, self.bilinear_repeat);
        Graphics.remove_sampler(renderer, self.bilinear_clamp_to_edge);
        Graphics.remove_sampler(renderer, self.point_repeat);
        Graphics.remove_sampler(renderer, self.point_clamp_to_edge);
        Graphics.remove_sampler(renderer, self.point_clamp_to_border);
    }
};

const RendererContext = struct {
    renderer: [*c]Graphics.Renderer = null,
    graphics_queue: [*c]Graphics.Queue = null,
    image_acquired_semaphore: [*c]Graphics.Semaphore = null,

    // Static samplers
    samplers: StaticSamplers = undefined,
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

    var fs_desc = std.mem.zeroes(FileSystem.FileSystemInitDesc);
    fs_desc.pAppName = "Tides Renderer";
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

    Graphics.add_semaphore(renderer_context.renderer, &renderer_context.image_acquired_semaphore);
    defer Graphics.remove_semaphore(renderer_context.renderer, renderer_context.image_acquired_semaphore);

    var resource_loader_desc = ResourceLoader.ResourceLoaderDesc{
        .mBufferSize = 256 * 1024 * 1024,
        .mBufferCount = 2,
        .mSingleThreaded = false,
        .mUseMaterials = false,
    };
    ResourceLoader.initResourceLoaderInterface(renderer_context.renderer, &resource_loader_desc);
    defer ResourceLoader.exitResourceLoaderInterface(renderer_context.renderer);

    renderer_context.samplers = StaticSamplers.init(renderer_context.renderer);
    defer renderer_context.samplers.exit(renderer_context.renderer);

    var is_running = true;
    while (is_running) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            is_running = false;
        }
    }
}
