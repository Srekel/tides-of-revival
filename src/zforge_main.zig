const std = @import("std");
const zforge = @import("zforge");
const zglfw = @import("zglfw");

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
    pub const data_buffer_count: u32 = 2;

    renderer: [*c]Graphics.Renderer = null,
    window: *window.Window = undefined,
    graphics_queue: [*c]Graphics.Queue = null,
    gpu_cmd_ring: Graphics.GpuCmdRing = undefined,
    image_acquired_semaphore: [*c]Graphics.Semaphore = null,
    frame_index: u32 = 0,
    samplers: StaticSamplers = undefined,
    default_vertex_layout: Graphics.VertexLayout = undefined,
    swap_chain: [*c]Graphics.SwapChain = null,

    pub const Error = error{
        NotInitialized,
        SwapChainNotInitialized,
    };

    pub fn init(wnd: *window.Window) Error!RendererContext {
        var renderer_context = RendererContext{};

        renderer_context.window = wnd;

        var renderer_desc = std.mem.zeroes(Graphics.RendererDesc);
        renderer_desc.mD3D11Supported = false;
        renderer_desc.mGLESSupported = false;
        renderer_desc.mShaderTarget = Graphics.ShaderTarget.SHADER_TARGET_6_6;
        renderer_desc.mDisableReloadServer = true;
        Graphics.initRenderer("Tides Renderer", &renderer_desc, &renderer_context.renderer);
        if (renderer_context.renderer == null) {
            std.log.err("Failed to initialize Z-Forge Renderer", .{});
            return Error.NotInitialized;
        }

        var queue_desc = std.mem.zeroes(Graphics.QueueDesc);
        queue_desc.mType = Graphics.QueueType.QUEUE_TYPE_GRAPHICS;
        queue_desc.mFlag = Graphics.QueueFlag.QUEUE_FLAG_INIT_MICROPROFILE;
        Graphics.add_queue(renderer_context.renderer, &queue_desc, &renderer_context.graphics_queue);

        var cmd_ring_desc: Graphics.GpuCmdRingDesc = undefined;
        cmd_ring_desc.queue = renderer_context.graphics_queue;
        cmd_ring_desc.pool_count = data_buffer_count;
        cmd_ring_desc.cmd_per_pool_count = 1;
        cmd_ring_desc.add_sync_primitives = true;
        renderer_context.gpu_cmd_ring = Graphics.GpuCmdRing.create(renderer_context.renderer, &cmd_ring_desc);

        Graphics.add_semaphore(renderer_context.renderer, &renderer_context.image_acquired_semaphore);

        var resource_loader_desc = ResourceLoader.ResourceLoaderDesc{
            .mBufferSize = 256 * 1024 * 1024,
            .mBufferCount = 2,
            .mSingleThreaded = false,
            .mUseMaterials = false,
        };
        ResourceLoader.initResourceLoaderInterface(renderer_context.renderer, &resource_loader_desc);

        renderer_context.samplers = StaticSamplers.init(renderer_context.renderer);

        // TODO(gmodarelli): Figure out how to support different vertex formats.
        // TODO(gmodarelli): Add support for color
        renderer_context.default_vertex_layout = std.mem.zeroes(Graphics.VertexLayout);
        renderer_context.default_vertex_layout.mBindingCount = 4;
        renderer_context.default_vertex_layout.mAttribCount = 4;
        renderer_context.default_vertex_layout.mAttribs[0].mSemantic = Graphics.ShaderSemantic.SEMANTIC_POSITION;
        renderer_context.default_vertex_layout.mAttribs[0].mFormat = Graphics.TinyImageFormat.R32G32B32_SFLOAT;
        renderer_context.default_vertex_layout.mAttribs[0].mBinding = 0;
        renderer_context.default_vertex_layout.mAttribs[0].mLocation = 0;
        renderer_context.default_vertex_layout.mAttribs[0].mOffset = 0;
        renderer_context.default_vertex_layout.mAttribs[1].mSemantic = Graphics.ShaderSemantic.SEMANTIC_NORMAL;
        renderer_context.default_vertex_layout.mAttribs[1].mFormat = Graphics.TinyImageFormat.R32_UINT;
        renderer_context.default_vertex_layout.mAttribs[1].mBinding = 1;
        renderer_context.default_vertex_layout.mAttribs[1].mLocation = 1;
        renderer_context.default_vertex_layout.mAttribs[1].mOffset = 0;
        renderer_context.default_vertex_layout.mAttribs[2].mSemantic = Graphics.ShaderSemantic.SEMANTIC_TANGENT;
        renderer_context.default_vertex_layout.mAttribs[2].mFormat = Graphics.TinyImageFormat.R32_UINT;
        renderer_context.default_vertex_layout.mAttribs[2].mBinding = 2;
        renderer_context.default_vertex_layout.mAttribs[2].mLocation = 2;
        renderer_context.default_vertex_layout.mAttribs[2].mOffset = 0;
        renderer_context.default_vertex_layout.mAttribs[3].mSemantic = Graphics.ShaderSemantic.SEMANTIC_TEXCOORD0;
        renderer_context.default_vertex_layout.mAttribs[3].mFormat = Graphics.TinyImageFormat.R32_UINT;
        renderer_context.default_vertex_layout.mAttribs[3].mBinding = 3;
        renderer_context.default_vertex_layout.mAttribs[3].mLocation = 3;
        renderer_context.default_vertex_layout.mAttribs[3].mOffset = 0;
        // renderer_context.default_vertex_layout.mAttribs[4].mSemantic = Graphics.ShaderSemantic.SEMANTIC_COLOR;
        // renderer_context.default_vertex_layout.mAttribs[4].mFormat = Graphics.TinyImageFormat.R8G8B8A8_UNORM;
        // renderer_context.default_vertex_layout.mAttribs[4].mBinding = 4;
        // renderer_context.default_vertex_layout.mAttribs[4].mLocation = 4;
        // renderer_context.default_vertex_layout.mAttribs[4].mOffset = 0;

        renderer_context.frame_index = 0;
        return renderer_context;
    }

    pub fn exit(self: *RendererContext) void {
        Graphics.remove_queue(self.renderer, self.graphics_queue);
        self.gpu_cmd_ring.destroy(self.renderer);
        Graphics.remove_semaphore(self.renderer, self.image_acquired_semaphore);
        ResourceLoader.exitResourceLoaderInterface(self.renderer);
        self.samplers.exit(self.renderer);
        Graphics.exitRenderer(self.renderer);
    }

    pub fn on_load(self: *RendererContext, reload_desc: Graphics.ReloadDesc) Error!void {
        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            if (!self.add_swapchain()) {
                return Error.SwapChainNotInitialized;
            }
        }
    }

    pub fn on_unload(self: *RendererContext, reload_desc: Graphics.ReloadDesc) void {
        Graphics.wait_queue_idle(self.graphics_queue);

        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            Graphics.remove_swap_chain(self.renderer, self.swap_chain);
        }
    }

    pub fn draw(self: *RendererContext) void {
        var swap_chain_image_index: u32 = 0;
        Graphics.acquire_next_image(self.renderer, self.swap_chain, self.image_acquired_semaphore, null, &swap_chain_image_index);
        const render_target = self.swap_chain.*.ppRenderTargets[swap_chain_image_index];

        var elem = self.gpu_cmd_ring.get_next_gpu_cmd_ring_element(true, 1);

        // Stall if CPU is running "data_buffer_count" frames ahead of GPU
        var fence_status: Graphics.FenceStatus = undefined;
        Graphics.get_fence_status(self.renderer, elem.?.fence, &fence_status);
        if (fence_status.bits == Graphics.FenceStatus.FENCE_STATUS_INCOMPLETE.bits) {
            Graphics.wait_for_fences(self.renderer, 1, &elem.?.fence);
        }

        Graphics.reset_cmd_pool(self.renderer, elem.?.cmd_pool);

        var cmd = elem.?.cmds[0];
        Graphics.begin_cmd(cmd);

        {
            var barrier = std.mem.zeroes(Graphics.RenderTargetBarrier);
            barrier.pRenderTarget = render_target;
            barrier.mCurrentState = Graphics.ResourceState.RESOURCE_STATE_PRESENT;
            barrier.mNewState = Graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
            Graphics.cmd_resource_barrier(cmd, 0, null, 0, null, 1, &barrier);
        }

        var bind_render_targets: Graphics.BindRenderTargetsDesc = undefined;
        bind_render_targets.mRenderTargetCount = 1;
        bind_render_targets.mRenderTargets[0] = std.mem.zeroes(Graphics.BindRenderTargetDesc);
        bind_render_targets.mRenderTargets[0].pRenderTarget = render_target;
        bind_render_targets.mRenderTargets[0].mLoadAction = Graphics.LoadActionType.LOAD_ACTION_CLEAR;
        bind_render_targets.mDepthStencil = std.mem.zeroes(Graphics.BindDepthTargetDesc);
        Graphics.cmd_bind_render_targets(cmd, &bind_render_targets);
        Graphics.cmd_set_viewport(cmd, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
        Graphics.cmd_set_scissor(cmd, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

        {
            var barrier = std.mem.zeroes(Graphics.RenderTargetBarrier);
            barrier.pRenderTarget = render_target;
            barrier.mCurrentState = Graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
            barrier.mNewState = Graphics.ResourceState.RESOURCE_STATE_PRESENT;
            Graphics.cmd_resource_barrier(cmd, 0, null, 0, null, 1, &barrier);
        }

        Graphics.end_cmd(cmd);

        var flush_update_desc: ResourceLoader.FlushResourceUpdateDesc = undefined;
        flush_update_desc.mNodeIndex = 0;
        ResourceLoader.flushResourceUpdates(&flush_update_desc);

        var wait_semaphores = [2]*Graphics.Semaphore{ flush_update_desc.pOutSubmittedSemaphore, self.image_acquired_semaphore };

        var submit_desc: Graphics.QueueSubmitDesc = undefined;
        submit_desc.mCmdCount = 1;
        submit_desc.mSignalSemaphoreCount = 1;
        submit_desc.mWaitSemaphoreCount = 2;
        submit_desc.ppCmds = &cmd;
        submit_desc.ppSignalSemaphores = &elem.?.semaphore;
        submit_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
        submit_desc.pSignalFence = elem.?.fence;
        Graphics.queue_submit(self.graphics_queue, &submit_desc);

        var queue_present_desc: Graphics.QueuePresentDesc = undefined;
        queue_present_desc.mIndex = @intCast(swap_chain_image_index);
        queue_present_desc.mWaitSemaphoreCount = 1;
        queue_present_desc.pSwapChain = self.swap_chain;
        queue_present_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
        queue_present_desc.mSubmitDone = true;
        Graphics.queue_present(self.graphics_queue, &queue_present_desc);

        self.frame_index = (self.frame_index + 1) % RendererContext.data_buffer_count;
    }

    fn add_swapchain(self: *RendererContext) bool {
        const native_handle = zglfw.native.getWin32Window(self.window.window) catch unreachable;

        const window_handle = Graphics.WindowHandle{
            .type = .WIN32,
            .window = native_handle,
        };

        var desc = std.mem.zeroes(Graphics.SwapChainDesc);
        desc.mWindowHandle = window_handle;
        desc.mPresentQueueCount = 1;
        desc.ppPresentQueues = &self.graphics_queue;
        desc.mWidth = @intCast(self.window.frame_buffer_size[0]);
        desc.mHeight = @intCast(self.window.frame_buffer_size[1]);
        desc.mImageCount = Graphics.get_recommended_swapchain_image_count(self.renderer, &window_handle);
        desc.mColorFormat = Graphics.get_supported_swapchain_format(self.renderer, &desc, Graphics.ColorSpace.COLOR_SPACE_SDR_SRGB);
        desc.mColorSpace = Graphics.ColorSpace.COLOR_SPACE_SDR_SRGB;
        desc.mEnableVsync = true;
        desc.mFlags = Graphics.SwapChainCreationFlags.SWAP_CHAIN_CREATION_FLAG_ENABLE_FOVEATED_RENDERING_VR;
        Graphics.add_swap_chain(self.renderer, &desc, &self.swap_chain);

        if (self.swap_chain == null) return false;

        return true;
    }
};

pub fn main() void {
    std.log.info("Did we make it? {}", .{zforge});

    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    var window_width = main_window.frame_buffer_size[0];
    var window_height = main_window.frame_buffer_size[1];

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

    var renderer_context = RendererContext.init(main_window) catch unreachable;
    defer renderer_context.exit();

    var reload_desc = Graphics.ReloadDesc{ .mType = .{ .RESIZE = true, .SHADER = true, .RENDERTARGET = true } };
    renderer_context.on_load(reload_desc) catch unreachable;
    defer renderer_context.on_unload(reload_desc);

    var is_running = true;
    while (is_running) {
        const window_status = window.update() catch unreachable;
        if (window_status == .no_windows) {
            is_running = false;
        }

        if (main_window.frame_buffer_size[0] != window_width or main_window.frame_buffer_size[1] != window_height) {
            window_width = main_window.frame_buffer_size[0];
            window_height = main_window.frame_buffer_size[1];

            reload_desc = Graphics.ReloadDesc{ .mType = .{ .RESIZE = true } };
            renderer_context.on_unload(reload_desc);
            renderer_context.on_load(reload_desc) catch unreachable;
        }

        renderer_context.draw();
    }
}
