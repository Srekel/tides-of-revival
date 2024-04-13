const std = @import("std");
const zforge = @import("zforge");
const zglfw = @import("zglfw");

const file_system = zforge.file_system;
const font = zforge.font;
const graphics = zforge.graphics;
const log = zforge.log;
const memory = zforge.memory;
const resource_loader = zforge.resource_loader;

const window = @import("renderer/window.zig");

const StaticSamplers = struct {
    bilinear_repeat: [*c]graphics.Sampler = null,
    bilinear_clamp_to_edge: [*c]graphics.Sampler = null,
    point_repeat: [*c]graphics.Sampler = null,
    point_clamp_to_edge: [*c]graphics.Sampler = null,
    point_clamp_to_border: [*c]graphics.Sampler = null,

    pub fn init(renderer: [*c]graphics.Renderer) StaticSamplers {
        var static_samplers = std.mem.zeroes(StaticSamplers);

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;
            graphics.add_sampler(renderer, &desc, &static_samplers.bilinear_repeat);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            graphics.add_sampler(renderer, &desc, &static_samplers.point_repeat);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;
            graphics.add_sampler(renderer, &desc, &static_samplers.bilinear_clamp_to_edge);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            graphics.add_sampler(renderer, &desc, &static_samplers.point_clamp_to_edge);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            graphics.add_sampler(renderer, &desc, &static_samplers.point_clamp_to_border);
        }

        return static_samplers;
    }

    pub fn exit(self: *StaticSamplers, renderer: [*c]graphics.Renderer) void {
        graphics.remove_sampler(renderer, self.bilinear_repeat);
        graphics.remove_sampler(renderer, self.bilinear_clamp_to_edge);
        graphics.remove_sampler(renderer, self.point_repeat);
        graphics.remove_sampler(renderer, self.point_clamp_to_edge);
        graphics.remove_sampler(renderer, self.point_clamp_to_border);
    }
};

const RendererContext = struct {
    pub const data_buffer_count: u32 = 2;

    renderer: [*c]graphics.Renderer = null,
    window: *window.Window = undefined,
    graphics_queue: [*c]graphics.Queue = null,
    gpu_cmd_ring: graphics.GpuCmdRing = undefined,
    image_acquired_semaphore: [*c]graphics.Semaphore = null,
    frame_index: u32 = 0,
    samplers: StaticSamplers = undefined,
    default_vertex_layout: graphics.VertexLayout = undefined,
    swap_chain: [*c]graphics.SwapChain = null,
    roboto_font_id: u32 = 0,

    pub const Error = error{
        NotInitialized,
        SwapChainNotInitialized,
        FontSystemNotInitialized,
    };

    pub fn init(wnd: *window.Window) Error!RendererContext {
        var renderer_context = RendererContext{};

        renderer_context.window = wnd;

        var renderer_desc = std.mem.zeroes(graphics.RendererDesc);
        renderer_desc.mD3D11Supported = false;
        renderer_desc.mGLESSupported = false;
        renderer_desc.mShaderTarget = graphics.ShaderTarget.SHADER_TARGET_6_6;
        renderer_desc.mDisableReloadServer = true;
        graphics.initRenderer("Tides Renderer", &renderer_desc, &renderer_context.renderer);
        if (renderer_context.renderer == null) {
            std.log.err("Failed to initialize Z-Forge Renderer", .{});
            return Error.NotInitialized;
        }

        var queue_desc = std.mem.zeroes(graphics.QueueDesc);
        queue_desc.mType = graphics.QueueType.QUEUE_TYPE_GRAPHICS;
        queue_desc.mFlag = graphics.QueueFlag.QUEUE_FLAG_INIT_MICROPROFILE;
        graphics.add_queue(renderer_context.renderer, &queue_desc, &renderer_context.graphics_queue);

        var cmd_ring_desc: graphics.GpuCmdRingDesc = undefined;
        cmd_ring_desc.queue = renderer_context.graphics_queue;
        cmd_ring_desc.pool_count = data_buffer_count;
        cmd_ring_desc.cmd_per_pool_count = 1;
        cmd_ring_desc.add_sync_primitives = true;
        renderer_context.gpu_cmd_ring = graphics.GpuCmdRing.create(renderer_context.renderer, &cmd_ring_desc);

        graphics.add_semaphore(renderer_context.renderer, &renderer_context.image_acquired_semaphore);

        var resource_loader_desc = resource_loader.ResourceLoaderDesc{
            .mBufferSize = 256 * 1024 * 1024,
            .mBufferCount = 2,
            .mSingleThreaded = false,
            .mUseMaterials = false,
        };
        resource_loader.initResourceLoaderInterface(renderer_context.renderer, &resource_loader_desc);

        // Load Roboto Font
        const font_desc = font.FontDesc{
            .pFontName = "Roboto",
            .pFontPath = "fonts/Roboto-Medium.ttf",
        };
        font.fntDefineFonts(&font_desc, 1, &renderer_context.roboto_font_id);

        var font_system_desc = font.FontSystemDesc{};
        font_system_desc.pRenderer = renderer_context.renderer;
        if (!font.initFontSystem(&font_system_desc)) {
            return Error.FontSystemNotInitialized;
        }

        renderer_context.samplers = StaticSamplers.init(renderer_context.renderer);

        // TODO(gmodarelli): Figure out how to support different vertex formats.
        // TODO(gmodarelli): Add support for color
        renderer_context.default_vertex_layout = std.mem.zeroes(graphics.VertexLayout);
        renderer_context.default_vertex_layout.mBindingCount = 4;
        renderer_context.default_vertex_layout.mAttribCount = 4;
        renderer_context.default_vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
        renderer_context.default_vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
        renderer_context.default_vertex_layout.mAttribs[0].mBinding = 0;
        renderer_context.default_vertex_layout.mAttribs[0].mLocation = 0;
        renderer_context.default_vertex_layout.mAttribs[0].mOffset = 0;
        renderer_context.default_vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_NORMAL;
        renderer_context.default_vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32_UINT;
        renderer_context.default_vertex_layout.mAttribs[1].mBinding = 1;
        renderer_context.default_vertex_layout.mAttribs[1].mLocation = 1;
        renderer_context.default_vertex_layout.mAttribs[1].mOffset = 0;
        renderer_context.default_vertex_layout.mAttribs[2].mSemantic = graphics.ShaderSemantic.SEMANTIC_TANGENT;
        renderer_context.default_vertex_layout.mAttribs[2].mFormat = graphics.TinyImageFormat.R32_UINT;
        renderer_context.default_vertex_layout.mAttribs[2].mBinding = 2;
        renderer_context.default_vertex_layout.mAttribs[2].mLocation = 2;
        renderer_context.default_vertex_layout.mAttribs[2].mOffset = 0;
        renderer_context.default_vertex_layout.mAttribs[3].mSemantic = graphics.ShaderSemantic.SEMANTIC_TEXCOORD0;
        renderer_context.default_vertex_layout.mAttribs[3].mFormat = graphics.TinyImageFormat.R32_UINT;
        renderer_context.default_vertex_layout.mAttribs[3].mBinding = 3;
        renderer_context.default_vertex_layout.mAttribs[3].mLocation = 3;
        renderer_context.default_vertex_layout.mAttribs[3].mOffset = 0;
        // renderer_context.default_vertex_layout.mAttribs[4].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
        // renderer_context.default_vertex_layout.mAttribs[4].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
        // renderer_context.default_vertex_layout.mAttribs[4].mBinding = 4;
        // renderer_context.default_vertex_layout.mAttribs[4].mLocation = 4;
        // renderer_context.default_vertex_layout.mAttribs[4].mOffset = 0;

        renderer_context.frame_index = 0;
        return renderer_context;
    }

    pub fn exit(self: *RendererContext) void {
        graphics.remove_queue(self.renderer, self.graphics_queue);
        self.gpu_cmd_ring.destroy(self.renderer);
        graphics.remove_semaphore(self.renderer, self.image_acquired_semaphore);
        font.exitFontSystem();
        resource_loader.exitResourceLoaderInterface(self.renderer);
        self.samplers.exit(self.renderer);
        graphics.exitRenderer(self.renderer);
    }

    pub fn on_load(self: *RendererContext, reload_desc: graphics.ReloadDesc) Error!void {
        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            if (!self.add_swapchain()) {
                return Error.SwapChainNotInitialized;
            }
        }

        var font_system_load_desc = std.mem.zeroes(font.FontSystemLoadDesc);
        font_system_load_desc.mLoadType = reload_desc.mType;
        font_system_load_desc.mColorFormat = @intFromEnum(self.swap_chain.*.ppRenderTargets[0].*.mFormat);
        font_system_load_desc.mDepthFormat = @intFromEnum(graphics.TinyImageFormat.D32_SFLOAT);
        font_system_load_desc.mDepthCompareMode = @intCast(graphics.CompareMode.CMP_EQUAL.bits);
        font_system_load_desc.mWidth = @intCast(self.window.frame_buffer_size[0]);
        font_system_load_desc.mHeight = @intCast(self.window.frame_buffer_size[1]);
        font.loadFontSystem(&font_system_load_desc);
    }

    pub fn on_unload(self: *RendererContext, reload_desc: graphics.ReloadDesc) void {
        graphics.wait_queue_idle(self.graphics_queue);

        font.unloadFontSystem(reload_desc.mType);

        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            graphics.remove_swap_chain(self.renderer, self.swap_chain);
        }
    }

    pub fn draw(self: *RendererContext) void {
        var swap_chain_image_index: u32 = 0;
        graphics.acquire_next_image(self.renderer, self.swap_chain, self.image_acquired_semaphore, null, &swap_chain_image_index);
        const render_target = self.swap_chain.*.ppRenderTargets[swap_chain_image_index];

        var elem = self.gpu_cmd_ring.getNextGpuCmdRingElement(true, 1).?;

        // Stall if CPU is running "data_buffer_count" frames ahead of GPU
        var fence_status: graphics.FenceStatus = undefined;
        graphics.get_fence_status(self.renderer, elem.fence, &fence_status);
        if (fence_status.bits == graphics.FenceStatus.FENCE_STATUS_INCOMPLETE.bits) {
            graphics.wait_for_fences(self.renderer, 1, &elem.fence);
        }

        graphics.reset_cmd_pool(self.renderer, elem.cmd_pool);

        var cmd = elem.cmds[0];
        graphics.begin_cmd(cmd);

        {
            var barrier = std.mem.zeroes(graphics.RenderTargetBarrier);
            barrier.pRenderTarget = render_target;
            barrier.mCurrentState = graphics.ResourceState.RESOURCE_STATE_PRESENT;
            barrier.mNewState = graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
            graphics.cmd_resource_barrier(cmd, 0, null, 0, null, 1, &barrier);
        }

        var bind_render_targets: graphics.BindRenderTargetsDesc = undefined;
        bind_render_targets.mRenderTargetCount = 1;
        bind_render_targets.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets.mRenderTargets[0].pRenderTarget = render_target;
        bind_render_targets.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
        bind_render_targets.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
        graphics.cmd_bind_render_targets(cmd, &bind_render_targets);
        graphics.cmd_set_viewport(cmd, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
        graphics.cmd_set_scissor(cmd, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

        var font_draw_desc = std.mem.zeroes(font.FontDrawDesc);
        font_draw_desc.pText = "Z-Forge !11!!";
        font_draw_desc.mFontID = self.roboto_font_id;
        font_draw_desc.mFontColor = 0xffffffff;
        font_draw_desc.mFontSize = 64;
        font.cmdDrawTextWithFont(cmd, 100.0, 100.0, &font_draw_desc);

        {
            var barrier = std.mem.zeroes(graphics.RenderTargetBarrier);
            barrier.pRenderTarget = render_target;
            barrier.mCurrentState = graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
            barrier.mNewState = graphics.ResourceState.RESOURCE_STATE_PRESENT;
            graphics.cmd_resource_barrier(cmd, 0, null, 0, null, 1, &barrier);
        }

        graphics.end_cmd(cmd);

        var flush_update_desc = std.mem.zeroes(resource_loader.FlushResourceUpdateDesc);
        flush_update_desc.mNodeIndex = 0;
        resource_loader.flushResourceUpdates(&flush_update_desc);

        var wait_semaphores = [2]*graphics.Semaphore{ flush_update_desc.pOutSubmittedSemaphore, self.image_acquired_semaphore };

        var submit_desc: graphics.QueueSubmitDesc = undefined;
        submit_desc.mCmdCount = 1;
        submit_desc.mSignalSemaphoreCount = 1;
        submit_desc.mWaitSemaphoreCount = 2;
        submit_desc.ppCmds = &cmd;
        submit_desc.ppSignalSemaphores = &elem.semaphore;
        submit_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
        submit_desc.pSignalFence = elem.fence;
        graphics.queue_submit(self.graphics_queue, &submit_desc);

        var queue_present_desc: graphics.QueuePresentDesc = undefined;
        queue_present_desc.mIndex = @intCast(swap_chain_image_index);
        queue_present_desc.mWaitSemaphoreCount = 1;
        queue_present_desc.pSwapChain = self.swap_chain;
        queue_present_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
        queue_present_desc.mSubmitDone = true;
        graphics.queue_present(self.graphics_queue, &queue_present_desc);

        self.frame_index = (self.frame_index + 1) % RendererContext.data_buffer_count;
    }

    fn add_swapchain(self: *RendererContext) bool {
        const native_handle = zglfw.native.getWin32Window(self.window.window) catch unreachable;

        const window_handle = graphics.WindowHandle{
            .type = .WIN32,
            .window = native_handle,
        };

        var desc = std.mem.zeroes(graphics.SwapChainDesc);
        desc.mWindowHandle = window_handle;
        desc.mPresentQueueCount = 1;
        desc.ppPresentQueues = &self.graphics_queue;
        desc.mWidth = @intCast(self.window.frame_buffer_size[0]);
        desc.mHeight = @intCast(self.window.frame_buffer_size[1]);
        desc.mImageCount = graphics.get_recommended_swapchain_image_count(self.renderer, &window_handle);
        desc.mColorFormat = graphics.get_supported_swapchain_format(self.renderer, &desc, graphics.ColorSpace.COLOR_SPACE_SDR_SRGB);
        desc.mColorSpace = graphics.ColorSpace.COLOR_SPACE_SDR_SRGB;
        desc.mEnableVsync = true;
        desc.mFlags = graphics.SwapChainCreationFlags.SWAP_CHAIN_CREATION_FLAG_ENABLE_FOVEATED_RENDERING_VR;
        graphics.add_swap_chain(self.renderer, &desc, &self.swap_chain);

        if (self.swap_chain == null) return false;

        return true;
    }
};

pub fn main() void {
    window.init(std.heap.page_allocator) catch unreachable;
    defer window.deinit();
    const main_window = window.createWindow("Tides of Revival: A Fort Wasn't Built In A Day") catch unreachable;
    var window_width = main_window.frame_buffer_size[0];
    var window_height = main_window.frame_buffer_size[1];

    if (!memory.initMemAlloc("Tides Renderer")) {
        std.log.err("Failed to initialize Z-Forge memory System", .{});
        return;
    }

    var fs_desc = std.mem.zeroes(file_system.FileSystemInitDesc);
    fs_desc.pAppName = "Tides Renderer";
    if (!file_system.initFileSystem(&fs_desc)) {
        std.log.err("Failed to initialize Z-Forge File System", .{});
        return;
    }
    defer file_system.exitFileSystem();

    if (!font.platform_init_font_system()) {
        std.log.err("Failed to initialize Plaftorm Font System", .{});
        return;
    }

    file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_DEBUG, file_system.ResourceDirectory.RD_LOG, "");

    log.init_log("Tides Renderer", log.LogLevel.eALL);
    defer log.exit_log();

    file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_GPU_CONFIG, "GPUCfg");
    file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_SHADER_BINARIES, "content/compiled_shaders");
    file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_TEXTURES, "content");
    file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_MESHES, "content");
    file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_FONTS, "content");

    var renderer_context = RendererContext.init(main_window) catch unreachable;
    defer renderer_context.exit();

    var reload_desc = graphics.ReloadDesc{ .mType = .{ .RESIZE = true, .SHADER = true, .RENDERTARGET = true } };
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

            reload_desc = graphics.ReloadDesc{ .mType = .{ .RESIZE = true } };
            renderer_context.on_unload(reload_desc);
            renderer_context.on_load(reload_desc) catch unreachable;
        }

        renderer_context.draw();
    }
}
