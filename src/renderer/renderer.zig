const std = @import("std");

const zforge = @import("zforge");
const zglfw = @import("zglfw");

const file_system = zforge.file_system;
const font = zforge.font;
const graphics = zforge.graphics;
const log = zforge.log;
const memory = zforge.memory;
const resource_loader = zforge.resource_loader;

const Pool = @import("zpool").Pool;

const window = @import("window.zig");

pub const ReloadDesc = graphics.ReloadDesc;

pub const Renderer = struct {
    pub const data_buffer_count: u32 = 2;

    renderer: [*c]graphics.Renderer = null,
    window: *window.Window = undefined,
    window_width: i32 = 0,
    window_height: i32 = 0,

    swap_chain: [*c]graphics.SwapChain = null,
    graphics_queue: [*c]graphics.Queue = null,
    gpu_cmd_ring: graphics.GpuCmdRing = undefined,
    image_acquired_semaphore: [*c]graphics.Semaphore = null,
    frame_index: u32 = 0,

    depth_buffer: [*c]graphics.RenderTarget,
    gbuffer_0: [*c]graphics.RenderTarget,
    gbuffer_1: [*c]graphics.RenderTarget,
    gbuffer_2: [*c]graphics.RenderTarget,
    scene_color: [*c]graphics.RenderTarget,

    samplers: StaticSamplers = undefined,
    default_vertex_layout: graphics.VertexLayout = undefined,
    roboto_font_id: u32 = 0,

    mesh_pool: MeshPool = undefined,
    texture_pool: TexturePool = undefined,
    buffer_pool: BufferPool = undefined,

    pub const Error = error{
        NotInitialized,
        SwapChainNotInitialized,
        FontSystemNotInitialized,
        MemorySystemNotInitialized,
        FileSystemNotInitialized,
    };

    pub fn init(wnd: *window.Window, allocator: std.mem.Allocator) Error!Renderer {
        var self = Renderer{};

        self.window = wnd;
        self.window_width = wnd.frame_buffer_size[0];
        self.window_height = wnd.frame_buffer_size[1];

        // Initialize The-Forge systems
        if (!memory.initMemAlloc("Tides Renderer")) {
            std.log.err("Failed to initialize Z-Forge memory System", .{});
            return Error.MemorySystemNotInitialized;
        }

        var fs_desc = std.mem.zeroes(file_system.FileSystemInitDesc);
        fs_desc.pAppName = "Tides Renderer";
        if (!file_system.initFileSystem(&fs_desc)) {
            std.log.err("Failed to initialize Z-Forge File System", .{});
            return Error.FileSystemNotInitialized;
        }

        if (!font.platformInitFontSystem()) {
            std.log.err("Failed to initialize Plaftorm Font System", .{});
            return Error.FontSystemNotInitialized;
        }

        file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_DEBUG, file_system.ResourceDirectory.RD_LOG, "");

        // log.initLog("Tides Renderer", log.LogLevel.eALL);

        file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_GPU_CONFIG, "GPUCfg");
        file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_SHADER_BINARIES, "content/compiled_shaders");
        file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_TEXTURES, "content");
        file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_MESHES, "content");
        file_system.fsSetPathForResourceDir(file_system.fsGetSystemFileIO(), file_system.ResourceMount.RM_CONTENT, file_system.ResourceDirectory.RD_FONTS, "content");

        var renderer_desc = std.mem.zeroes(graphics.RendererDesc);
        renderer_desc.mD3D11Supported = false;
        renderer_desc.mGLESSupported = false;
        renderer_desc.mShaderTarget = graphics.ShaderTarget.SHADER_TARGET_6_6;
        renderer_desc.mDisableReloadServer = true;
        graphics.initRenderer("Tides Renderer", &renderer_desc, &self.renderer);
        if (self.renderer == null) {
            std.log.err("Failed to initialize Z-Forge Renderer", .{});
            return Error.NotInitialized;
        }

        var queue_desc = std.mem.zeroes(graphics.QueueDesc);
        queue_desc.mType = graphics.QueueType.QUEUE_TYPE_GRAPHICS;
        queue_desc.mFlag = graphics.QueueFlag.QUEUE_FLAG_INIT_MICROPROFILE;
        graphics.addQueue(self.renderer, &queue_desc, &self.graphics_queue);

        var cmd_ring_desc: graphics.GpuCmdRingDesc = undefined;
        cmd_ring_desc.queue = self.graphics_queue;
        cmd_ring_desc.pool_count = data_buffer_count;
        cmd_ring_desc.cmd_per_pool_count = 1;
        cmd_ring_desc.add_sync_primitives = true;
        self.gpu_cmd_ring = graphics.GpuCmdRing.create(self.renderer, &cmd_ring_desc);

        graphics.addSemaphore(self.renderer, &self.image_acquired_semaphore);

        var resource_loader_desc = resource_loader.ResourceLoaderDesc{
            .mBufferSize = 256 * 1024 * 1024,
            .mBufferCount = 2,
            .mSingleThreaded = false,
            .mUseMaterials = false,
        };
        resource_loader.initResourceLoaderInterface(self.renderer, &resource_loader_desc);

        // Load Roboto Font
        const font_desc = font.FontDesc{
            .pFontName = "Roboto",
            .pFontPath = "fonts/Roboto-Medium.ttf",
        };
        font.fntDefineFonts(&font_desc, 1, &self.roboto_font_id);

        var font_system_desc = font.FontSystemDesc{};
        font_system_desc.pRenderer = self.renderer;
        if (!font.initFontSystem(&font_system_desc)) {
            return Error.FontSystemNotInitialized;
        }

        self.samplers = StaticSamplers.init(self.renderer);

        self.default_vertex_layout = std.mem.zeroes(graphics.VertexLayout);
        self.default_vertex_layout.mBindingCount = 4;
        self.default_vertex_layout.mAttribCount = 4;
        self.default_vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.POSITION;
        self.default_vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
        self.default_vertex_layout.mAttribs[0].mBinding = 0;
        self.default_vertex_layout.mAttribs[0].mLocation = 0;
        self.default_vertex_layout.mAttribs[0].mOffset = 0;
        self.default_vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.NORMAL;
        self.default_vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32_UINT;
        self.default_vertex_layout.mAttribs[1].mBinding = 1;
        self.default_vertex_layout.mAttribs[1].mLocation = 1;
        self.default_vertex_layout.mAttribs[1].mOffset = 0;
        self.default_vertex_layout.mAttribs[2].mSemantic = graphics.ShaderSemantic.TANGENT;
        self.default_vertex_layout.mAttribs[2].mFormat = graphics.TinyImageFormat.R32_UINT;
        self.default_vertex_layout.mAttribs[2].mBinding = 2;
        self.default_vertex_layout.mAttribs[2].mLocation = 2;
        self.default_vertex_layout.mAttribs[2].mOffset = 0;
        self.default_vertex_layout.mAttribs[3].mSemantic = graphics.ShaderSemantic.TEXCOORD0;
        self.default_vertex_layout.mAttribs[3].mFormat = graphics.TinyImageFormat.R32_UINT;
        self.default_vertex_layout.mAttribs[3].mBinding = 3;
        self.default_vertex_layout.mAttribs[3].mLocation = 3;
        self.default_vertex_layout.mAttribs[3].mOffset = 0;

        self.frame_index = 0;

        self.mesh_pool = MeshPool.initMaxCapacity(allocator) catch unreachable;
        self.texture_pool = TexturePool.initMaxCapacity(allocator) catch unreachable;
        self.buffer_pool = BufferPool.initMaxCapacity(allocator) catch unreachable;
        return self;
    }

    pub fn exit(self: *Renderer) void {
        var buffer_handles = self.buffer_pool.liveHandles();
        while (buffer_handles.next()) |handle| {
            var buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
            resource_loader.removeResource(@ptrCast(&buffer));
        }
        self.buffer_pool.deinit();

        var texture_handles = self.texture_pool.liveHandles();
        while (texture_handles.next()) |handle| {
            const texture = self.texture_pool.getColumn(handle, .texture) catch unreachable;
            resource_loader.removeResource__Overload2(@ptrCast(texture));
        }
        self.texture_pool.deinit();

        var mesh_handles = self.mesh_pool.liveHandles();
        while (mesh_handles.next()) |handle| {
            const mesh = self.mesh_pool.getColumn(handle, .mesh) catch unreachable;
            resource_loader.removeResource__Overload3(mesh.geometry);
            resource_loader.removeGeometryBuffer(mesh.buffer);
            resource_loader.removeResource__Overload4(mesh.data);
        }
        self.mesh_pool.deinit();

        graphics.removeQueue(self.renderer, self.graphics_queue);
        self.gpu_cmd_ring.destroy(self.renderer);
        graphics.removeSemaphore(self.renderer, self.image_acquired_semaphore);
        font.exitFontSystem();
        resource_loader.exitResourceLoaderInterface(self.renderer);
        self.samplers.exit(self.renderer);
        graphics.exitRenderer(self.renderer);

        font.platformExitFontSystem();
        // log.exitLog();
        file_system.exitFileSystem();
    }

    pub fn onLoad(self: *Renderer, reload_desc: graphics.ReloadDesc) Error!void {
        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            if (!self.addSwapchain()) {
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

    pub fn onUnload(self: *Renderer, reload_desc: graphics.ReloadDesc) void {
        graphics.waitQueueIdle(self.graphics_queue);

        font.unloadFontSystem(reload_desc.mType);

        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            graphics.removeSwapChain(self.renderer, self.swap_chain);
        }
    }

    pub fn draw(self: *Renderer, delta_time: f32) void {
        _ = delta_time;

        var swap_chain_image_index: u32 = 0;
        graphics.acquireNextImage(self.renderer, self.swap_chain, self.image_acquired_semaphore, null, &swap_chain_image_index);
        const render_target = self.swap_chain.*.ppRenderTargets[swap_chain_image_index];

        var elem = self.gpu_cmd_ring.getNextGpuCmdRingElement(true, 1).?;

        // Stall if CPU is running "data_buffer_count" frames ahead of GPU
        var fence_status: graphics.FenceStatus = undefined;
        graphics.getFenceStatus(self.renderer, elem.fence, &fence_status);
        if (fence_status.bits == graphics.FenceStatus.FENCE_STATUS_INCOMPLETE.bits) {
            graphics.waitForFences(self.renderer, 1, &elem.fence);
        }

        graphics.resetCmdPool(self.renderer, elem.cmd_pool);

        var cmd = elem.cmds[0];
        graphics.beginCmd(cmd);

        {
            var barrier = std.mem.zeroes(graphics.RenderTargetBarrier);
            barrier.pRenderTarget = render_target;
            barrier.mCurrentState = graphics.ResourceState.RESOURCE_STATE_PRESENT;
            barrier.mNewState = graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
            graphics.cmdResourceBarrier(cmd, 0, null, 0, null, 1, &barrier);
        }

        var bind_render_targets: graphics.BindRenderTargetsDesc = undefined;
        bind_render_targets.mRenderTargetCount = 1;
        bind_render_targets.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
        bind_render_targets.mRenderTargets[0].pRenderTarget = render_target;
        bind_render_targets.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
        bind_render_targets.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
        graphics.cmdBindRenderTargets(cmd, &bind_render_targets);
        graphics.cmdSetViewport(cmd, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
        graphics.cmdSetScissor(cmd, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

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
            graphics.cmdResourceBarrier(cmd, 0, null, 0, null, 1, &barrier);
        }

        graphics.endCmd(cmd);

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
        graphics.queueSubmit(self.graphics_queue, &submit_desc);

        var queue_present_desc: graphics.QueuePresentDesc = undefined;
        queue_present_desc.mIndex = @intCast(swap_chain_image_index);
        queue_present_desc.mWaitSemaphoreCount = 1;
        queue_present_desc.pSwapChain = self.swap_chain;
        queue_present_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
        queue_present_desc.mSubmitDone = true;
        graphics.queuePresent(self.graphics_queue, &queue_present_desc);

        self.frame_index = (self.frame_index + 1) % Renderer.data_buffer_count;
    }

    pub fn loadMesh(self: *Renderer, path: [:0]const u8) !MeshHandle {
        var mesh: Mesh = undefined;
        mesh.geometry = null;
        mesh.buffer = null;
        mesh.data = null;

        mesh.buffer_layout_desc.mSemanticBindings = std.mem.zeroes([19]u32);
        mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.POSITION)] = 0;
        mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.NORMAL)] = 1;
        mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TANGENT)] = 2;
        mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TEXCOORD0)] = 3;

        mesh.buffer_layout_desc.mVerticesStrides[0] = @sizeOf(f32) * 3;
        mesh.buffer_layout_desc.mVerticesStrides[1] = @sizeOf(u32);
        mesh.buffer_layout_desc.mVerticesStrides[2] = @sizeOf(u32);
        mesh.buffer_layout_desc.mVerticesStrides[3] = @sizeOf(u32);

        const index_count_max: u32 = 1024 * 1024;
        const vertex_count_max: u32 = 1024 * 1024;
        var buffer_load_desc = std.mem.zeroes(resource_loader.GeometryBufferLoadDesc);
        buffer_load_desc.mStartState = @intCast(graphics.ResourceState.RESOURCE_STATE_COPY_DEST.bits);
        buffer_load_desc.pOutGeometryBuffer = &mesh.buffer;
        buffer_load_desc.mIndicesSize = @sizeOf(u32) * index_count_max;
        buffer_load_desc.mVerticesSizes[0] = mesh.buffer_layout_desc.mVerticesStrides[0] * vertex_count_max;
        buffer_load_desc.mVerticesSizes[1] = mesh.buffer_layout_desc.mVerticesStrides[1] * vertex_count_max;
        buffer_load_desc.mVerticesSizes[2] = mesh.buffer_layout_desc.mVerticesStrides[2] * vertex_count_max;
        buffer_load_desc.mVerticesSizes[3] = mesh.buffer_layout_desc.mVerticesStrides[3] * vertex_count_max;
        buffer_load_desc.pNameIndexBuffer = "Indices";
        buffer_load_desc.pNamesVertexBuffers[0] = "Positions";
        buffer_load_desc.pNamesVertexBuffers[1] = "Normals";
        buffer_load_desc.pNamesVertexBuffers[2] = "Tangents";
        buffer_load_desc.pNamesVertexBuffers[3] = "UVs";
        resource_loader.addGeometryBuffer(&buffer_load_desc);

        var load_desc = std.mem.zeroes(resource_loader.GeometryLoadDesc);
        load_desc.pFileName = path;
        load_desc.pVertexLayout = &self.default_vertex_layout;
        load_desc.pGeometryBuffer = mesh.buffer;
        load_desc.pGeometryBufferLayoutDesc = &mesh.buffer_layout_desc;
        load_desc.ppGeometry = &mesh.geometry;
        load_desc.ppGeometryData = &mesh.data;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource__Overload3(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        mesh.loaded = true;

        const handle: MeshHandle = try self.mesh_pool.add(.{ .mesh = mesh });
        return handle;
    }

    pub fn loadTexture(self: *Renderer, path: [:0]const u8) TextureHandle {
        // var texture = std.mem.zeroes(graphics.Texture);
        var texture: [*c]graphics.Texture = null;
        std.log.debug("Loading texture at path: {s}", .{path});

        var desc = std.mem.zeroes(graphics.TextureDesc);
        desc.bBindless = true;
        var load_desc = std.mem.zeroes(resource_loader.TextureLoadDesc);
        load_desc.__union_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0);
        load_desc.__union_field1.__struct_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0.__Struct0);
        load_desc.pFileName = path;
        load_desc.__union_field1.__struct_field1.pDesc = &desc;
        load_desc.ppTexture = @ptrCast(&texture);

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource__Overload2(&load_desc, &token);
        resource_loader.waitForToken(&token);

        const handle: TextureHandle = self.texture_pool.add(.{ .texture = texture }) catch unreachable;
        return handle;
    }

    pub fn loadTextureFromMemory(self: *Renderer, width: u32, height: u32, format: graphics.TinyImageFormat, data_slice: Slice, debug_name: [*:0]const u8) TextureHandle {
        // var texture = std.mem.zeroes(graphics.Texture);
        var texture: [*c]graphics.Texture = null;

        var desc = std.mem.zeroes(graphics.TextureDesc);
        desc.mWidth = width;
        desc.mHeight = height;
        desc.mFormat = format;
        desc.mDepth = 1;
        desc.mMipLevels = 1;
        desc.mArraySize = 1;
        desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
        desc.mSampleQuality = 0;
        desc.pName = debug_name;
        desc.bBindless = true;
        desc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE;

        var load_desc = std.mem.zeroes(resource_loader.TextureLoadDesc);
        load_desc.pFileName = null;
        load_desc.__union_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0);
        load_desc.__union_field1.__struct_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0.__Struct0);
        load_desc.__union_field1.__struct_field1.pDesc = &desc;
        load_desc.ppTexture = @ptrCast(&texture);
        load_desc.pTextureData = data_slice.data;
        load_desc.mTextureDataSize = data_slice.size;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource__Overload2(&load_desc, &token);
        resource_loader.waitForToken(&token);

        const handle: TextureHandle = self.texture_pool.add(.{ .texture = texture }) catch unreachable;
        return handle;
    }

    pub fn getTextureBindlessIndex(self: *Renderer, handle: TextureHandle) u32 {
        const texture = self.texture_pool.getColumn(handle, .texture) catch unreachable;
        const bindless_index = texture.mDx.mDescriptors;
        return @intCast(bindless_index);
    }

    pub fn createBuffer(self: *Renderer, initial_data: Slice, data_stride: u32, debug_name: [:0]const u8) BufferHandle {
        _ = data_stride;
        _ = debug_name;

        var buffer: [*c]graphics.Buffer = null;

        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.bBindless = true;
        load_desc.mDesc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW;
        load_desc.mDesc.mFlags = graphics.BufferCreationFlags.BUFFER_CREATION_FLAG_SHADER_DEVICE_ADDRESS;
        load_desc.mDesc.mMemoryUsage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_GPU_ONLY;
        if (initial_data.data) |data| {
            load_desc.mDesc.mSize = initial_data.size;
            // NOTE(gmodarelli): The persistent SRV uses a R32_TYPELESS representation, so we need to provide an element count in terms of 32bit data
            load_desc.mDesc.mElementCount = @intCast(initial_data.size / @sizeOf(u32));
            load_desc.mDesc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            load_desc.pData = data;
        }
        load_desc.ppBuffer = &buffer;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        const handle: BufferHandle = self.buffer_pool.add(.{ .buffer = buffer }) catch unreachable;
        return handle;
    }

    pub fn updateBuffer(self: *Renderer, data: Slice, handle: BufferHandle) void {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;

        var update_desc = std.mem.zeroes(resource_loader.BufferUpdateDesc);
        update_desc.pBuffer = @ptrCast(buffer);
        resource_loader.beginUpdateResource(&update_desc);
        @memcpy(update_desc.pMappedData, data.data);
        resource_loader.endUpdateResource(&update_desc);
    }

    pub fn getBufferBindlessIndex(self: *Renderer, handle: BufferHandle) u32 {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        const bindless_index = buffer.mDx.mDescriptors;
        return @intCast(bindless_index);
    }

    fn addSwapchain(self: *Renderer) bool {
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
        desc.mImageCount = graphics.getRecommendedSwapchainImageCount(self.renderer, &window_handle);
        desc.mColorFormat = graphics.getSupportedSwapchainFormat(self.renderer, &desc, graphics.ColorSpace.COLOR_SPACE_SDR_SRGB);
        desc.mColorSpace = graphics.ColorSpace.COLOR_SPACE_SDR_SRGB;
        desc.mEnableVsync = true;
        desc.mFlags = graphics.SwapChainCreationFlags.SWAP_CHAIN_CREATION_FLAG_ENABLE_FOVEATED_RENDERING_VR;
        graphics.addSwapChain(self.renderer, &desc, &self.swap_chain);

        if (self.swap_chain == null) return false;

        return true;
    }
};

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
            graphics.addSampler(renderer, &desc, &static_samplers.bilinear_repeat);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            graphics.addSampler(renderer, &desc, &static_samplers.point_repeat);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;
            graphics.addSampler(renderer, &desc, &static_samplers.bilinear_clamp_to_edge);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            graphics.addSampler(renderer, &desc, &static_samplers.point_clamp_to_edge);
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;
            graphics.addSampler(renderer, &desc, &static_samplers.point_clamp_to_border);
        }

        return static_samplers;
    }

    pub fn exit(self: *StaticSamplers, renderer: [*c]graphics.Renderer) void {
        graphics.removeSampler(renderer, self.bilinear_repeat);
        graphics.removeSampler(renderer, self.bilinear_clamp_to_edge);
        graphics.removeSampler(renderer, self.point_repeat);
        graphics.removeSampler(renderer, self.point_clamp_to_edge);
        graphics.removeSampler(renderer, self.point_clamp_to_border);
    }
};

pub const Mesh = struct {
    geometry: [*c]resource_loader.Geometry,
    data: [*c]resource_loader.GeometryData,
    buffer: [*c]resource_loader.GeometryBuffer,
    buffer_layout_desc: resource_loader.GeometryBufferLayoutDesc,
    loaded: bool,
};

const MeshPool = Pool(16, 16, Mesh, struct { mesh: Mesh });
pub const MeshHandle = MeshPool.Handle;

const TexturePool = Pool(16, 16, graphics.Texture, struct { texture: [*c]graphics.Texture });
pub const TextureHandle = TexturePool.Handle;

const BufferPool = Pool(16, 16, graphics.Buffer, struct { buffer: [*c]graphics.Buffer });
pub const BufferHandle = BufferPool.Handle;

pub const Slice = extern struct {
    data: ?*const anyopaque,
    size: u64,
};

pub const OutputMode = enum(u32) { SDR = 0, P2020 = 1, COUNT = 2 };

pub const buffered_frames_count: u32 = 2;
pub const sub_mesh_max_count: u32 = 32;

pub fn frameIndex() u32 {
    return TR_frameIndex();
}
extern fn TR_frameIndex() u32;

pub fn requestReload(reload_desc: *const ReloadDesc) bool {
    return TR_requestReload(reload_desc);
}
extern fn TR_requestReload(reload_desc: *const ReloadDesc) bool;

pub fn onLoad(reload_desc: *ReloadDesc) bool {
    return TR_onLoad(reload_desc);
}
extern fn TR_onLoad(reload_desc: *ReloadDesc) bool;

pub fn onUnload(reload_desc: *ReloadDesc) void {
    TR_onUnload(reload_desc);
}
extern fn TR_onUnload(reload_desc: *ReloadDesc) void;

pub const HackyLightBuffersIndices = struct {
    directional_lights_buffer_index: u32,
    point_lights_buffer_index: u32,
    directional_lights_count: u32,
    point_lights_count: u32,
};

pub const HackyUIBuffersIndices = struct {
    ui_instance_buffer_index: u32,
    ui_instance_count: u32,
};

pub const FrameData = extern struct {
    view_matrix: [16]f32,
    proj_matrix: [16]f32,
    position: [3]f32,
    directional_lights_buffer_index: u32,
    point_lights_buffer_index: u32,
    directional_lights_count: u32,
    point_lights_count: u32,
    skybox_mesh_handle: MeshHandle,
    ui_instance_buffer_index: u32,
    ui_instance_count: u32,
};

pub const PointLight = extern struct {
    position: [3]f32,
    radius: f32,
    color: [3]f32,
    intensity: f32,
};

pub const DirectionalLight = extern struct {
    direction: [3]f32,
    shadow_map: i32,
    color: [3]f32,
    intensity: f32,
    shadow_range: f32,
    _pad: [2]f32,
    shadow_map_dimensions: i32,
    view_proj: [16]f32,
};

pub const point_lights_count_max: u32 = 1024;
pub const directional_lights_count_max: u32 = 8;

pub fn getSubMeshCount(mesh_handle: MeshHandle) u32 {
    return TR_getSubMeshCount(mesh_handle);
}
extern fn TR_getSubMeshCount(mesh_handle: MeshHandle) u32;

pub const DrawCallInstanced = struct {
    mesh_handle: MeshHandle,
    sub_mesh_index: u32,
    start_instance_location: u32,
    instance_count: u32,
};

pub const DrawCallPushConstants = struct {
    start_instance_location: u32,
    instance_data_buffer_index: u32,
    instance_material_buffer_index: u32,
};

pub fn registerTerrainDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void {
    TR_registerTerrainDrawCalls(draw_calls_slice, push_constants_slice);
}
extern fn TR_registerTerrainDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void;

pub fn registerLitOpaqueDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void {
    TR_registerLitOpaqueDrawCalls(draw_calls_slice, push_constants_slice);
}
extern fn TR_registerLitOpaqueDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void;

pub fn registerLitMaskedDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void {
    TR_registerLitMaskedDrawCalls(draw_calls_slice, push_constants_slice);
}
extern fn TR_registerLitMaskedDrawCalls(draw_calls_slice: Slice, push_constants_slice: Slice) void;

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

pub const TinyImageFormat = enum(u32) {
    UNDEFINED = 0,
    R1_UNORM = 1,
    R2_UNORM = 2,
    R4_UNORM = 3,
    R4G4_UNORM = 4,
    G4R4_UNORM = 5,
    A8_UNORM = 6,
    R8_UNORM = 7,
    R8_SNORM = 8,
    R8_UINT = 9,
    R8_SINT = 10,
    R8_SRGB = 11,
    B2G3R3_UNORM = 12,
    R4G4B4A4_UNORM = 13,
    R4G4B4X4_UNORM = 14,
    B4G4R4A4_UNORM = 15,
    B4G4R4X4_UNORM = 16,
    A4R4G4B4_UNORM = 17,
    X4R4G4B4_UNORM = 18,
    A4B4G4R4_UNORM = 19,
    X4B4G4R4_UNORM = 20,
    R5G6B5_UNORM = 21,
    B5G6R5_UNORM = 22,
    R5G5B5A1_UNORM = 23,
    B5G5R5A1_UNORM = 24,
    A1B5G5R5_UNORM = 25,
    A1R5G5B5_UNORM = 26,
    R5G5B5X1_UNORM = 27,
    B5G5R5X1_UNORM = 28,
    X1R5G5B5_UNORM = 29,
    X1B5G5R5_UNORM = 30,
    B2G3R3A8_UNORM = 31,
    R8G8_UNORM = 32,
    R8G8_SNORM = 33,
    G8R8_UNORM = 34,
    G8R8_SNORM = 35,
    R8G8_UINT = 36,
    R8G8_SINT = 37,
    R8G8_SRGB = 38,
    R16_UNORM = 39,
    R16_SNORM = 40,
    R16_UINT = 41,
    R16_SINT = 42,
    R16_SFLOAT = 43,
    R16_SBFLOAT = 44,
    R8G8B8_UNORM = 45,
    R8G8B8_SNORM = 46,
    R8G8B8_UINT = 47,
    R8G8B8_SINT = 48,
    R8G8B8_SRGB = 49,
    B8G8R8_UNORM = 50,
    B8G8R8_SNORM = 51,
    B8G8R8_UINT = 52,
    B8G8R8_SINT = 53,
    B8G8R8_SRGB = 54,
    R8G8B8A8_UNORM = 55,
    R8G8B8A8_SNORM = 56,
    R8G8B8A8_UINT = 57,
    R8G8B8A8_SINT = 58,
    R8G8B8A8_SRGB = 59,
    B8G8R8A8_UNORM = 60,
    B8G8R8A8_SNORM = 61,
    B8G8R8A8_UINT = 62,
    B8G8R8A8_SINT = 63,
    B8G8R8A8_SRGB = 64,
    R8G8B8X8_UNORM = 65,
    B8G8R8X8_UNORM = 66,
    R16G16_UNORM = 67,
    G16R16_UNORM = 68,
    R16G16_SNORM = 69,
    G16R16_SNORM = 70,
    R16G16_UINT = 71,
    R16G16_SINT = 72,
    R16G16_SFLOAT = 73,
    R16G16_SBFLOAT = 74,
    R32_UINT = 75,
    R32_SINT = 76,
    R32_SFLOAT = 77,
    A2R10G10B10_UNORM = 78,
    A2R10G10B10_UINT = 79,
    A2R10G10B10_SNORM = 80,
    A2R10G10B10_SINT = 81,
    A2B10G10R10_UNORM = 82,
    A2B10G10R10_UINT = 83,
    A2B10G10R10_SNORM = 84,
    A2B10G10R10_SINT = 85,
    R10G10B10A2_UNORM = 86,
    R10G10B10A2_UINT = 87,
    R10G10B10A2_SNORM = 88,
    R10G10B10A2_SINT = 89,
    B10G10R10A2_UNORM = 90,
    B10G10R10A2_UINT = 91,
    B10G10R10A2_SNORM = 92,
    B10G10R10A2_SINT = 93,
    B10G11R11_UFLOAT = 94,
    E5B9G9R9_UFLOAT = 95,
    R16G16B16_UNORM = 96,
    R16G16B16_SNORM = 97,
    R16G16B16_UINT = 98,
    R16G16B16_SINT = 99,
    R16G16B16_SFLOAT = 100,
    R16G16B16_SBFLOAT = 101,
    R16G16B16A16_UNORM = 102,
    R16G16B16A16_SNORM = 103,
    R16G16B16A16_UINT = 104,
    R16G16B16A16_SINT = 105,
    R16G16B16A16_SFLOAT = 106,
    R16G16B16A16_SBFLOAT = 107,
    R32G32_UINT = 108,
    R32G32_SINT = 109,
    R32G32_SFLOAT = 110,
    R32G32B32_UINT = 111,
    R32G32B32_SINT = 112,
    R32G32B32_SFLOAT = 113,
    R32G32B32A32_UINT = 114,
    R32G32B32A32_SINT = 115,
    R32G32B32A32_SFLOAT = 116,
    R64_UINT = 117,
    R64_SINT = 118,
    R64_SFLOAT = 119,
    R64G64_UINT = 120,
    R64G64_SINT = 121,
    R64G64_SFLOAT = 122,
    R64G64B64_UINT = 123,
    R64G64B64_SINT = 124,
    R64G64B64_SFLOAT = 125,
    R64G64B64A64_UINT = 126,
    R64G64B64A64_SINT = 127,
    R64G64B64A64_SFLOAT = 128,
    D16_UNORM = 129,
    X8_D24_UNORM = 130,
    D32_SFLOAT = 131,
    S8_UINT = 132,
    D16_UNORM_S8_UINT = 133,
    D24_UNORM_S8_UINT = 134,
    D32_SFLOAT_S8_UINT = 135,
    DXBC1_RGB_UNORM = 136,
    DXBC1_RGB_SRGB = 137,
    DXBC1_RGBA_UNORM = 138,
    DXBC1_RGBA_SRGB = 139,
    DXBC2_UNORM = 140,
    DXBC2_SRGB = 141,
    DXBC3_UNORM = 142,
    DXBC3_SRGB = 143,
    DXBC4_UNORM = 144,
    DXBC4_SNORM = 145,
    DXBC5_UNORM = 146,
    DXBC5_SNORM = 147,
    DXBC6H_UFLOAT = 148,
    DXBC6H_SFLOAT = 149,
    DXBC7_UNORM = 150,
    DXBC7_SRGB = 151,
    PVRTC1_2BPP_UNORM = 152,
    PVRTC1_4BPP_UNORM = 153,
    PVRTC2_2BPP_UNORM = 154,
    PVRTC2_4BPP_UNORM = 155,
    PVRTC1_2BPP_SRGB = 156,
    PVRTC1_4BPP_SRGB = 157,
    PVRTC2_2BPP_SRGB = 158,
    PVRTC2_4BPP_SRGB = 159,
    ETC2_R8G8B8_UNORM = 160,
    ETC2_R8G8B8_SRGB = 161,
    ETC2_R8G8B8A1_UNORM = 162,
    ETC2_R8G8B8A1_SRGB = 163,
    ETC2_R8G8B8A8_UNORM = 164,
    ETC2_R8G8B8A8_SRGB = 165,
    ETC2_EAC_R11_UNORM = 166,
    ETC2_EAC_R11_SNORM = 167,
    ETC2_EAC_R11G11_UNORM = 168,
    ETC2_EAC_R11G11_SNORM = 169,
    ASTC_4x4_UNORM = 170,
    ASTC_4x4_SRGB = 171,
    ASTC_5x4_UNORM = 172,
    ASTC_5x4_SRGB = 173,
    ASTC_5x5_UNORM = 174,
    ASTC_5x5_SRGB = 175,
    ASTC_6x5_UNORM = 176,
    ASTC_6x5_SRGB = 177,
    ASTC_6x6_UNORM = 178,
    ASTC_6x6_SRGB = 179,
    ASTC_8x5_UNORM = 180,
    ASTC_8x5_SRGB = 181,
    ASTC_8x6_UNORM = 182,
    ASTC_8x6_SRGB = 183,
    ASTC_8x8_UNORM = 184,
    ASTC_8x8_SRGB = 185,
    ASTC_10x5_UNORM = 186,
    ASTC_10x5_SRGB = 187,
    ASTC_10x6_UNORM = 188,
    ASTC_10x6_SRGB = 189,
    ASTC_10x8_UNORM = 190,
    ASTC_10x8_SRGB = 191,
    ASTC_10x10_UNORM = 192,
    ASTC_10x10_SRGB = 193,
    ASTC_12x10_UNORM = 194,
    ASTC_12x10_SRGB = 195,
    ASTC_12x12_UNORM = 196,
    ASTC_12x12_SRGB = 197,
    CLUT_P4 = 198,
    CLUT_P4A4 = 199,
    CLUT_P8 = 200,
    CLUT_P8A8 = 201,
    R4G4B4A4_UNORM_PACK16 = 202,
    B4G4R4A4_UNORM_PACK16 = 203,
    R5G6B5_UNORM_PACK16 = 204,
    B5G6R5_UNORM_PACK16 = 205,
    R5G5B5A1_UNORM_PACK16 = 206,
    B5G5R5A1_UNORM_PACK16 = 207,
    A1R5G5B5_UNORM_PACK16 = 208,
    G16B16G16R16_422_UNORM = 209,
    B16G16R16G16_422_UNORM = 210,
    R12X4G12X4B12X4A12X4_UNORM_4PACK16 = 211,
    G12X4B12X4G12X4R12X4_422_UNORM_4PACK16 = 212,
    B12X4G12X4R12X4G12X4_422_UNORM_4PACK16 = 213,
    R10X6G10X6B10X6A10X6_UNORM_4PACK16 = 214,
    G10X6B10X6G10X6R10X6_422_UNORM_4PACK16 = 215,
    B10X6G10X6R10X6G10X6_422_UNORM_4PACK16 = 216,
    G8B8G8R8_422_UNORM = 217,
    B8G8R8G8_422_UNORM = 218,
    G8_B8_R8_3PLANE_420_UNORM = 219,
    G8_B8R8_2PLANE_420_UNORM = 220,
    G8_B8_R8_3PLANE_422_UNORM = 221,
    G8_B8R8_2PLANE_422_UNORM = 222,
    G8_B8_R8_3PLANE_444_UNORM = 223,
    G10X6_B10X6_R10X6_3PLANE_420_UNORM_3PACK16 = 224,
    G10X6_B10X6_R10X6_3PLANE_422_UNORM_3PACK16 = 225,
    G10X6_B10X6_R10X6_3PLANE_444_UNORM_3PACK16 = 226,
    G10X6_B10X6R10X6_2PLANE_420_UNORM_3PACK16 = 227,
    G10X6_B10X6R10X6_2PLANE_422_UNORM_3PACK16 = 228,
    G12X4_B12X4_R12X4_3PLANE_420_UNORM_3PACK16 = 229,
    G12X4_B12X4_R12X4_3PLANE_422_UNORM_3PACK16 = 230,
    G12X4_B12X4_R12X4_3PLANE_444_UNORM_3PACK16 = 231,
    G12X4_B12X4R12X4_2PLANE_420_UNORM_3PACK16 = 232,
    G12X4_B12X4R12X4_2PLANE_422_UNORM_3PACK16 = 233,
    G16_B16_R16_3PLANE_420_UNORM = 234,
    G16_B16_R16_3PLANE_422_UNORM = 235,
    G16_B16_R16_3PLANE_444_UNORM = 236,
    G16_B16R16_2PLANE_420_UNORM = 237,
    G16_B16R16_2PLANE_422_UNORM = 238,
};
