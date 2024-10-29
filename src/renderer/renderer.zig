const std = @import("std");

const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const zforge = @import("zforge");
const zglfw = @import("zglfw");
const zgui = @import("zgui");

const file_system = zforge.file_system;
const font = zforge.font;
const graphics = zforge.graphics;
const log = zforge.log;
const memory = zforge.memory;
const profiler = zforge.profiler;
const resource_loader = zforge.resource_loader;
const util = @import("../util.zig");
const ztracy = @import("ztracy");

const atmosphere_render_pass = @import("../systems/renderer_system/atmosphere_render_pass.zig");

const Pool = @import("zpool").Pool;

const window = @import("window.zig");

pub const ReloadDesc = graphics.ReloadDesc;

pub const renderPassRenderFn = ?*const fn (cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void;
pub const renderPassImGuiFn = ?*const fn (user_data: *anyopaque) void;
pub const renderPassRenderShadowMapFn = ?*const fn (cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void;
pub const renderPassCreateDescriptorSetsFn = ?*const fn (user_data: *anyopaque) void;
pub const renderPassPrepareDescriptorSetsFn = ?*const fn (user_data: *anyopaque) void;
pub const renderPassUnloadDescriptorSetsFn = ?*const fn (user_data: *anyopaque) void;

pub const opaque_pipelines = [_]IdLocal{
    IdLocal.init("lit"),
    IdLocal.init("shadows_lit"),
    IdLocal.init("tree"),
    IdLocal.init("shadows_tree"),
};

pub const masked_pipelines = [_]IdLocal{
    IdLocal.init("lit_masked"),
    IdLocal.init("shadows_lit_masked"),
    IdLocal.init("tree_masked"),
    IdLocal.init("shadows_tree_masked"),
};

const VertexLayoutHashMap = std.AutoHashMap(IdLocal, graphics.VertexLayout);

pub const Renderer = struct {
    pub const data_buffer_count: u32 = 2;

    allocator: std.mem.Allocator = undefined,
    renderer: [*c]graphics.Renderer = null,
    window: *window.Window = undefined,
    window_width: i32 = 0,
    window_height: i32 = 0,
    time: f32 = 0.0,
    vsync_enabled: bool = false,
    atmosphere_scattering_enabled: bool = true,
    ibl_enabled: bool = true,

    swap_chain: [*c]graphics.SwapChain = null,
    gpu_cmd_ring: graphics.GpuCmdRing = undefined,
    image_acquired_semaphore: [*c]graphics.Semaphore = null,
    swap_chain_image_index: u32 = 0,
    graphics_queue: [*c]graphics.Queue = null,
    frame_index: u32 = 0,

    gpu_profile_token: profiler.ProfileToken = undefined,
    shadow_pass_profile_token: profiler.ProfileToken = undefined,
    gbuffer_pass_profile_token: profiler.ProfileToken = undefined,
    deferred_pass_profile_token: profiler.ProfileToken = undefined,
    skybox_pass_profile_token: profiler.ProfileToken = undefined,
    atmosphere_pass_profile_token: profiler.ProfileToken = undefined,
    tonemap_pass_profile_token: profiler.ProfileToken = undefined,
    imgui_pass_profile_token: profiler.ProfileToken = undefined,

    depth_buffer: [*c]graphics.RenderTarget = null,
    shadow_depth_buffer: [*c]graphics.RenderTarget = null,
    gbuffer_0: [*c]graphics.RenderTarget = null,
    gbuffer_1: [*c]graphics.RenderTarget = null,
    gbuffer_2: [*c]graphics.RenderTarget = null,
    scene_color: [*c]graphics.RenderTarget = null,

    // Resolution Independent Render Targets
    transmittance_lut: [*c]graphics.RenderTarget = null,

    samplers: StaticSamplers = undefined,
    vertex_layouts_map: VertexLayoutHashMap = undefined,
    roboto_font_id: u32 = 0,

    material_pool: MaterialPool = undefined,
    materials: std.ArrayList(Material) = undefined,
    materials_buffer: BufferHandle = undefined,

    mesh_pool: MeshPool = undefined,
    texture_pool: TexturePool = undefined,
    buffer_pool: BufferPool = undefined,
    pso_pool: PSOPool = undefined,
    pso_map: PSOMap = undefined,

    render_terrain_pass_user_data: ?*anyopaque = null,
    render_terrain_pass_imgui_fn: renderPassImGuiFn = null,
    render_terrain_pass_render_fn: renderPassRenderFn = null,
    render_terrain_pass_render_shadow_map_fn: renderPassRenderShadowMapFn = null,
    render_terrain_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_terrain_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_terrain_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_gbuffer_pass_user_data: ?*anyopaque = null,
    render_gbuffer_pass_imgui_fn: renderPassImGuiFn = null,
    render_gbuffer_pass_render_fn: renderPassRenderFn = null,
    render_gbuffer_pass_render_shadow_map_fn: renderPassRenderShadowMapFn = null,
    render_gbuffer_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_gbuffer_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_gbuffer_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_deferred_shading_pass_user_data: ?*anyopaque = null,
    render_deferred_shading_pass_imgui_fn: renderPassImGuiFn = null,
    render_deferred_shading_pass_render_fn: renderPassRenderFn = null,
    render_deferred_shading_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_deferred_shading_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_deferred_shading_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_skybox_pass_user_data: ?*anyopaque = null,
    render_skybox_pass_imgui_fn: renderPassImGuiFn = null,
    render_skybox_pass_render_fn: renderPassRenderFn = null,
    render_skybox_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_skybox_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_skybox_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_atmosphere_pass_user_data: ?*anyopaque = null,
    render_atmosphere_pass_imgui_fn: renderPassImGuiFn = null,
    render_atmosphere_pass_render_fn: renderPassRenderFn = null,
    render_atmosphere_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_atmosphere_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_atmosphere_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_tonemap_pass_user_data: ?*anyopaque = null,
    render_tonemap_pass_imgui_fn: renderPassImGuiFn = null,
    render_tonemap_pass_render_fn: renderPassRenderFn = null,
    render_tonemap_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_tonemap_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_tonemap_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_imgui: bool = false,
    render_ui_pass_user_data: ?*anyopaque = null,
    render_ui_pass_imgui_fn: renderPassImGuiFn = null,
    render_ui_pass_render_fn: renderPassRenderFn = null,
    render_ui_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_ui_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_ui_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    render_im3d_pass_user_data: ?*anyopaque = null,
    render_im3d_pass_imgui_fn: renderPassImGuiFn = null,
    render_im3d_pass_render_fn: renderPassRenderFn = null,
    render_im3d_pass_create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    render_im3d_pass_prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    render_im3d_pass_unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    pub const Error = error{
        NotInitialized,
        SwapChainNotInitialized,
        FontSystemNotInitialized,
        MemorySystemNotInitialized,
        FileSystemNotInitialized,
    };

    pub fn init(wnd: *window.Window, allocator: std.mem.Allocator) Error!Renderer {
        var self = Renderer{};

        self.allocator = allocator;

        self.window = wnd;
        self.window_width = wnd.frame_buffer_size[0];
        self.window_height = wnd.frame_buffer_size[1];
        self.time = 0.0;
        self.vsync_enabled = false;
        self.atmosphere_scattering_enabled = true;
        self.ibl_enabled = true;

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

        log.initLog("Tides Renderer", log.LogLevel.eALL);

        var renderer_desc = std.mem.zeroes(graphics.RendererDesc);
        graphics.initGPUConfiguration(null);
        graphics.initRenderer("Tides Renderer", &renderer_desc, &self.renderer);
        if (self.renderer == null) {
            std.log.err("Failed to initialize Z-Forge Renderer", .{});
            return Error.NotInitialized;
        }

        var queue_desc = std.mem.zeroes(graphics.QueueDesc);
        queue_desc.mType = graphics.QueueType.QUEUE_TYPE_GRAPHICS;
        queue_desc.mFlag = graphics.QueueFlag.QUEUE_FLAG_INIT_MICROPROFILE;
        graphics.initQueue(self.renderer, &queue_desc, &self.graphics_queue);

        var cmd_ring_desc: graphics.GpuCmdRingDesc = undefined;
        cmd_ring_desc.queue = self.graphics_queue;
        cmd_ring_desc.pool_count = data_buffer_count;
        cmd_ring_desc.cmd_per_pool_count = 1;
        cmd_ring_desc.add_sync_primitives = true;
        self.gpu_cmd_ring = graphics.GpuCmdRing.create(self.renderer, &cmd_ring_desc);

        graphics.initSemaphore(self.renderer, &self.image_acquired_semaphore);

        var resource_loader_desc = resource_loader.ResourceLoaderDesc{
            .mBufferSize = 256 * 1024 * 1024,
            .mBufferCount = 2,
            .mSingleThreaded = false,
            .mUseMaterials = false,
        };
        resource_loader.initResourceLoaderInterface(self.renderer, &resource_loader_desc);

        self.createResolutionIndependentRenderTargets();

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

        var profiler_desc = profiler.ProfilerDesc{};
        profiler_desc.pRenderer = self.renderer;
        profiler.initProfiler(&profiler_desc);
        self.gpu_profile_token = profiler.initGpuProfiler(self.renderer, self.graphics_queue, "Graphics");

        self.samplers = StaticSamplers.init(self.renderer);

        self.vertex_layouts_map = VertexLayoutHashMap.init(allocator);

        var imgui_vertex_layout = std.mem.zeroes(graphics.VertexLayout);
        imgui_vertex_layout.mBindingCount = 1;
        imgui_vertex_layout.mAttribCount = 3;
        imgui_vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
        imgui_vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
        imgui_vertex_layout.mAttribs[0].mBinding = 0;
        imgui_vertex_layout.mAttribs[0].mLocation = 0;
        imgui_vertex_layout.mAttribs[0].mOffset = 0;
        imgui_vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_TEXCOORD0;
        imgui_vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
        imgui_vertex_layout.mAttribs[1].mBinding = 0;
        imgui_vertex_layout.mAttribs[1].mLocation = 1;
        imgui_vertex_layout.mAttribs[1].mOffset = @sizeOf(f32) * 2;
        imgui_vertex_layout.mAttribs[2].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
        imgui_vertex_layout.mAttribs[2].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
        imgui_vertex_layout.mAttribs[2].mBinding = 0;
        imgui_vertex_layout.mAttribs[2].mLocation = 2;
        imgui_vertex_layout.mAttribs[2].mOffset = @sizeOf(f32) * 4;
        self.vertex_layouts_map.put(IdLocal.init("imgui"), imgui_vertex_layout) catch unreachable;

        var im3d_vertex_layout = std.mem.zeroes(graphics.VertexLayout);
        im3d_vertex_layout.mBindingCount = 1;
        im3d_vertex_layout.mAttribCount = 2;
        im3d_vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
        im3d_vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32A32_SFLOAT;
        im3d_vertex_layout.mAttribs[0].mBinding = 0;
        im3d_vertex_layout.mAttribs[0].mLocation = 0;
        im3d_vertex_layout.mAttribs[0].mOffset = 0;
        im3d_vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
        im3d_vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
        im3d_vertex_layout.mAttribs[1].mBinding = 0;
        im3d_vertex_layout.mAttribs[1].mLocation = 1;
        im3d_vertex_layout.mAttribs[1].mOffset = @sizeOf(f32) * 4;
        self.vertex_layouts_map.put(IdLocal.init("im3d"), im3d_vertex_layout) catch unreachable;

        {
            var vertex_layout = std.mem.zeroes(graphics.VertexLayout);

            vertex_layout.mBindingCount = 3;
            vertex_layout.mAttribCount = 3;
            vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
            vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
            vertex_layout.mAttribs[0].mBinding = 0;
            vertex_layout.mAttribs[0].mLocation = 0;
            vertex_layout.mAttribs[0].mOffset = 0;
            vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_TEXCOORD0;
            vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32_UINT;
            vertex_layout.mAttribs[1].mBinding = 1;
            vertex_layout.mAttribs[1].mLocation = 1;
            vertex_layout.mAttribs[1].mOffset = 0;
            vertex_layout.mAttribs[2].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
            vertex_layout.mAttribs[2].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
            vertex_layout.mAttribs[2].mBinding = 2;
            vertex_layout.mAttribs[2].mLocation = 2;
            vertex_layout.mAttribs[2].mOffset = 0;
            self.vertex_layouts_map.put(IdLocal.init("pos_uv0_col"), vertex_layout) catch unreachable;

            vertex_layout.mBindingCount = 5;
            vertex_layout.mAttribCount = 5;
            vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
            vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
            vertex_layout.mAttribs[0].mBinding = 0;
            vertex_layout.mAttribs[0].mLocation = 0;
            vertex_layout.mAttribs[0].mOffset = 0;
            vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_NORMAL;
            vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32_UINT;
            vertex_layout.mAttribs[1].mBinding = 1;
            vertex_layout.mAttribs[1].mLocation = 1;
            vertex_layout.mAttribs[1].mOffset = 0;
            // TODO(gmodarelli): Encode tangent into a smaller representation
            vertex_layout.mAttribs[2].mSemantic = graphics.ShaderSemantic.SEMANTIC_TANGENT;
            vertex_layout.mAttribs[2].mFormat = graphics.TinyImageFormat.R32G32B32A32_SFLOAT;
            vertex_layout.mAttribs[2].mBinding = 2;
            vertex_layout.mAttribs[2].mLocation = 2;
            vertex_layout.mAttribs[2].mOffset = 0;
            vertex_layout.mAttribs[3].mSemantic = graphics.ShaderSemantic.SEMANTIC_TEXCOORD0;
            vertex_layout.mAttribs[3].mFormat = graphics.TinyImageFormat.R32_UINT;
            vertex_layout.mAttribs[3].mBinding = 3;
            vertex_layout.mAttribs[3].mLocation = 3;
            vertex_layout.mAttribs[3].mOffset = 0;
            vertex_layout.mAttribs[4].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
            vertex_layout.mAttribs[4].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
            vertex_layout.mAttribs[4].mBinding = 4;
            vertex_layout.mAttribs[4].mLocation = 4;
            vertex_layout.mAttribs[4].mOffset = 0;
            self.vertex_layouts_map.put(IdLocal.init("pos_uv0_nor_tan_col"), vertex_layout) catch unreachable;

            vertex_layout.mBindingCount = 6;
            vertex_layout.mAttribCount = 6;
            vertex_layout.mAttribs[5].mSemantic = graphics.ShaderSemantic.SEMANTIC_TEXCOORD1;
            vertex_layout.mAttribs[5].mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
            vertex_layout.mAttribs[5].mBinding = 5;
            vertex_layout.mAttribs[5].mLocation = 5;
            vertex_layout.mAttribs[5].mOffset = 0;
            self.vertex_layouts_map.put(IdLocal.init("pos_uv0_nor_tan_col_uv1"), vertex_layout) catch unreachable;
        }

        self.frame_index = 0;

        self.mesh_pool = MeshPool.initMaxCapacity(allocator) catch unreachable;
        self.texture_pool = TexturePool.initMaxCapacity(allocator) catch unreachable;
        self.buffer_pool = BufferPool.initMaxCapacity(allocator) catch unreachable;
        self.pso_pool = PSOPool.initMaxCapacity(allocator) catch unreachable;
        self.pso_map = PSOMap.init(allocator);

        self.material_pool = MaterialPool.initMaxCapacity(allocator) catch unreachable;
        self.materials = std.ArrayList(Material).init(allocator);
        const buffer_data = Slice{
            .data = null,
            .size = 1000 * @sizeOf(Material),
        };
        self.materials_buffer = self.createBindlessBuffer(buffer_data, "Materials Buffer");

        zgui.init(allocator);
        _ = zgui.io.addFontFromFile("content/fonts/Roboto-Medium.ttf", 16.0);

        return self;
    }

    pub fn exit(self: *Renderer) void {
        var shader_handles = self.pso_pool.liveHandles();
        while (shader_handles.next()) |handle| {
            const pipeline = self.pso_pool.getColumn(handle, .pipeline) catch unreachable;
            graphics.removePipeline(self.renderer, pipeline);

            const root_signature = self.pso_pool.getColumn(handle, .root_signature) catch unreachable;
            graphics.removeRootSignature(self.renderer, root_signature);

            const shader = self.pso_pool.getColumn(handle, .shader) catch unreachable;
            graphics.removeShader(self.renderer, shader);
        }
        self.pso_pool.deinit();
        self.pso_map.deinit();

        var buffer_handles = self.buffer_pool.liveHandles();
        while (buffer_handles.next()) |handle| {
            const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
            resource_loader.removeResource(@ptrCast(buffer));
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

        // TODO(juice): Clean gpu resources
        self.material_pool.deinit();
        self.materials.deinit();

        self.vertex_layouts_map.deinit();

        graphics.exitQueue(self.renderer, self.graphics_queue);
        self.gpu_cmd_ring.destroy(self.renderer);
        graphics.exitSemaphore(self.renderer, self.image_acquired_semaphore);

        profiler.exitGpuProfiler(self.gpu_profile_token);
        profiler.exitProfiler();

        self.destroyResolutionIndependentRenderTargets();

        font.exitFontSystem();
        resource_loader.exitResourceLoaderInterface(self.renderer);
        self.samplers.exit(self.renderer);
        graphics.exitRenderer(self.renderer);

        font.platformExitFontSystem();
        log.exitLog();
        file_system.exitFileSystem();
    }

    pub fn onLoad(self: *Renderer, reload_desc: graphics.ReloadDesc) Error!void {
        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            if (!self.addSwapchain()) {
                return Error.SwapChainNotInitialized;
            }

            self.createRenderTargets();
        }

        if (reload_desc.mType.SHADER) {
            self.createPipelines();

            const rtv_format = self.swap_chain.*.ppRenderTargets[0].*.mFormat;
            const pipeline_id = IdLocal.init("imgui");
            const pipeline = self.getPSO(pipeline_id);
            const root_signature = self.getRootSignature(pipeline_id);
            const heap = self.renderer.*.mDx.pCbvSrvUavHeaps[0].pHeap;
            const cpu_desc_handle = self.renderer.*.mDx.pCbvSrvUavHeaps[0].mStartCpuHandle;
            const gpu_desc_handle = self.renderer.*.mDx.pCbvSrvUavHeaps[0].mStartGpuHandle;

            zgui.backend.init(
                self.window.window,
                self.renderer.*.mDx.pDevice,
                data_buffer_count,
                @intFromEnum(rtv_format),
                heap,
                root_signature.*.mDx.pRootSignature,
                pipeline.*.mDx.__union_field1.pPipelineState,
                @as(zgui.backend.D3D12_CPU_DESCRIPTOR_HANDLE, @bitCast(cpu_desc_handle)),
                @as(zgui.backend.D3D12_GPU_DESCRIPTOR_HANDLE, @bitCast(gpu_desc_handle)),
            );

            if (self.render_terrain_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_terrain_pass_user_data.?);
            }

            if (self.render_gbuffer_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_gbuffer_pass_user_data.?);
            }

            if (self.render_deferred_shading_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_deferred_shading_pass_user_data.?);
            }

            if (self.render_skybox_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_skybox_pass_user_data.?);
            }

            if (self.render_atmosphere_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_atmosphere_pass_user_data.?);
            }

            if (self.render_tonemap_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_tonemap_pass_user_data.?);
            }

            if (self.render_ui_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_ui_pass_user_data.?);
            }

            if (self.render_im3d_pass_create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                create_descriptor_sets_fn(self.render_im3d_pass_user_data.?);
            }
        }

        if (self.render_terrain_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_terrain_pass_user_data.?);
        }

        if (self.render_gbuffer_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_gbuffer_pass_user_data.?);
        }

        if (self.render_deferred_shading_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_deferred_shading_pass_user_data.?);
        }

        if (self.render_skybox_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_skybox_pass_user_data.?);
        }

        if (self.render_atmosphere_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_atmosphere_pass_user_data.?);
        }

        if (self.render_tonemap_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_tonemap_pass_user_data.?);
        }

        if (self.render_ui_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_ui_pass_user_data.?);
        }

        if (self.render_im3d_pass_prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
            prepare_descriptor_sets_fn(self.render_im3d_pass_user_data.?);
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

        if (reload_desc.mType.SHADER) {
            self.destroyPipelines();
            zgui.backend.deinit();
        }

        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            graphics.removeSwapChain(self.renderer, self.swap_chain);
            self.destroyRenderTargets();
        }

        if (reload_desc.mType.SHADER) {
            if (self.render_terrain_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_terrain_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_gbuffer_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_gbuffer_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_deferred_shading_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_deferred_shading_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_skybox_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_skybox_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_atmosphere_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_atmosphere_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_tonemap_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_tonemap_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_ui_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_ui_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }

            if (self.render_im3d_pass_unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                if (self.render_im3d_pass_user_data) |user_data| {
                    unload_descriptor_sets_fn(user_data);
                }
            }
        }
    }

    pub fn requestReload(self: *Renderer, reload_desc: graphics.ReloadDesc) void {
        self.onUnload(reload_desc);
        self.onLoad(reload_desc) catch unreachable;
    }

    pub fn toggleVSync(self: *Renderer) void {
        self.vsync_enabled = !self.vsync_enabled;
    }

    pub fn reloadShaders(self: *Renderer) void {
        const reload_desc = graphics.ReloadDesc{
            .mType = .{ .SHADER = true },
        };
        self.requestReload(reload_desc);
    }

    pub fn draw(self: *Renderer) void {
        if (self.render_imgui) {
            zgui.setNextWindowSize(.{ .w = 600, .h = 1000, .cond = .first_use_ever });
            if (!zgui.begin("Renderer Settings", .{})) {
                zgui.end();
            } else {
                // GPU Profiler
                {
                    if (zgui.collapsingHeader("Performance", .{ .default_open = true })) {
                        zgui.text("GPU Average time: {d}", .{profiler.getGpuProfileAvgTime(self.gpu_profile_token)});

                        zgui.text("\tShadow Map Pass: {d}", .{profiler.getGpuProfileAvgTime(self.shadow_pass_profile_token)});
                        zgui.text("\tGBuffer Pass: {d}", .{profiler.getGpuProfileAvgTime(self.gbuffer_pass_profile_token)});
                        zgui.text("\tDeferred Shading Pass: {d}", .{profiler.getGpuProfileAvgTime(self.deferred_pass_profile_token)});
                        zgui.text("\tSkybox Pass: {d}", .{profiler.getGpuProfileAvgTime(self.skybox_pass_profile_token)});
                        zgui.text("\tAtmosphere Pass: {d}", .{profiler.getGpuProfileAvgTime(self.atmosphere_pass_profile_token)});
                        zgui.text("\tTonemap Pass: {d}", .{profiler.getGpuProfileAvgTime(self.tonemap_pass_profile_token)});
                        zgui.text("\tImGUI Pass: {d}", .{profiler.getGpuProfileAvgTime(self.imgui_pass_profile_token)});
                    }
                }

                // Renderer Settings
                {
                    if (zgui.collapsingHeader("Renderer", .{ .default_open = true })) {
                        _ = zgui.checkbox("VSync", .{ .v = &self.vsync_enabled });
                        _ = zgui.checkbox("Atmosphere Scattering", .{ .v = &self.atmosphere_scattering_enabled });
                        _ = zgui.checkbox("IBL", .{ .v = &self.ibl_enabled });
                    }
                }

                if (self.render_terrain_pass_imgui_fn) |render_fn| {
                    if (self.render_terrain_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_gbuffer_pass_imgui_fn) |render_fn| {
                    if (self.render_gbuffer_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_deferred_shading_pass_imgui_fn) |render_fn| {
                    if (self.render_deferred_shading_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_skybox_pass_imgui_fn) |render_fn| {
                    if (self.render_skybox_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_atmosphere_pass_imgui_fn) |render_fn| {
                    if (self.render_atmosphere_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_tonemap_pass_imgui_fn) |render_fn| {
                    if (self.render_tonemap_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_ui_pass_imgui_fn) |render_fn| {
                    if (self.render_ui_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }

                if (self.render_im3d_pass_imgui_fn) |render_fn| {
                    if (self.render_im3d_pass_user_data) |user_data| {
                        render_fn(user_data);
                    }
                }
                zgui.end();
            }
        }

        const trazy_zone = ztracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer trazy_zone.End();

        if ((self.swap_chain.*.bitfield_1.mEnableVsync == 1) != self.vsync_enabled) {
            graphics.waitQueueIdle(self.graphics_queue);
            graphics.toggleVSync(self.renderer, &self.swap_chain);
        }

        var swap_chain_image_index: u32 = 0;
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Acquire Next Image", 0x00_ff_00_00);
            defer trazy_zone1.End();
            graphics.acquireNextImage(self.renderer, self.swap_chain, self.image_acquired_semaphore, null, &swap_chain_image_index);
        }

        var elem = self.gpu_cmd_ring.getNextGpuCmdRingElement(true, 1).?;

        // Stall if CPU is running "data_buffer_count" frames ahead of GPU
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Wait for GPU", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var fence_status: graphics.FenceStatus = undefined;
            graphics.getFenceStatus(self.renderer, elem.fence, &fence_status);
            if (fence_status.bits == graphics.FenceStatus.FENCE_STATUS_INCOMPLETE.bits) {
                graphics.waitForFences(self.renderer, 1, &elem.fence);
            }
        }

        graphics.resetCmdPool(self.renderer, elem.cmd_pool);

        var cmd_list = elem.cmds[0];
        graphics.beginCmd(cmd_list);

        profiler.cmdBeginGpuFrameProfile(cmd_list, self.gpu_profile_token, .{ .bUseMarker = true });

        // Shadow Map Pass
        {
            self.shadow_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Shadow Map Pass", .{ .bUseMarker = true });

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Shadow Map Pass", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.shadow_depth_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_DEPTH_WRITE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 0;
            bind_render_targets_desc.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
            bind_render_targets_desc.mDepthStencil.pDepthStencil = self.shadow_depth_buffer;
            bind_render_targets_desc.mDepthStencil.mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, 2048.0, 2048.0, 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, 2048, 2048);

            if (self.render_terrain_pass_render_shadow_map_fn) |render_fn| {
                if (self.render_terrain_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            if (self.render_gbuffer_pass_render_shadow_map_fn) |render_fn| {
                if (self.render_gbuffer_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);

            profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);
        }

        // GBuffer Pass
        {
            self.gbuffer_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "GBuffer Pass", .{ .bUseMarker = true });

            const trazy_zone1 = ztracy.ZoneNC(@src(), "GBuffer Pass", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.gbuffer_0, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.gbuffer_1, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.gbuffer_2, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.depth_buffer, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_DEPTH_WRITE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 3;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.gbuffer_0;
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            bind_render_targets_desc.mRenderTargets[1] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[1].pRenderTarget = self.gbuffer_1;
            bind_render_targets_desc.mRenderTargets[1].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            bind_render_targets_desc.mRenderTargets[2] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[2].pRenderTarget = self.gbuffer_2;
            bind_render_targets_desc.mRenderTargets[2].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            bind_render_targets_desc.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
            bind_render_targets_desc.mDepthStencil.pDepthStencil = self.depth_buffer;
            bind_render_targets_desc.mDepthStencil.mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            if (self.render_terrain_pass_render_fn) |render_fn| {
                if (self.render_terrain_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            if (self.render_gbuffer_pass_render_fn) |render_fn| {
                if (self.render_gbuffer_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);

            profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);
        }

        // Deferred Shading
        {
            self.deferred_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Deferred Shading", .{ .bUseMarker = true });

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Deferred Shading", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.scene_color, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.gbuffer_0, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.gbuffer_1, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.gbuffer_2, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.depth_buffer, graphics.ResourceState.RESOURCE_STATE_DEPTH_WRITE, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.shadow_depth_buffer, graphics.ResourceState.RESOURCE_STATE_DEPTH_WRITE, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.scene_color;
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            if (self.render_deferred_shading_pass_render_fn) |render_fn| {
                if (self.render_deferred_shading_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            if (!self.atmosphere_scattering_enabled) {
                if (self.render_skybox_pass_render_fn) |render_fn| {
                    if (self.render_skybox_pass_user_data) |user_data| {
                        render_fn(cmd_list, user_data);
                    }
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);

            profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);
        }

        // Atmospheric Scattering Pass
        if (self.atmosphere_scattering_enabled) {
            self.atmosphere_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Atmosphere", .{ .bUseMarker = true });

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Atmosphere", 0x00_ff_00_00);
            defer trazy_zone1.End();

            if (self.render_atmosphere_pass_render_fn) |render_fn| {
                if (self.render_atmosphere_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);

            profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);
        }

        // Tonemap & UI Passes
        {
            self.tonemap_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Tonemap & UI Passes", .{ .bUseMarker = true });

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Tonemap & UI Passes", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.scene_color, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.swap_chain.*.ppRenderTargets[swap_chain_image_index], graphics.ResourceState.RESOURCE_STATE_PRESENT, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.swap_chain.*.ppRenderTargets[swap_chain_image_index];
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            if (self.render_tonemap_pass_render_fn) |render_fn| {
                if (self.render_tonemap_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            if (self.render_im3d_pass_render_fn) |render_fn| {
                if (self.render_im3d_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            if (self.render_ui_pass_render_fn) |render_fn| {
                if (self.render_ui_pass_user_data) |user_data| {
                    render_fn(cmd_list, user_data);
                }
            }

            profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);
        }

        // ImGUI Pass
        if (self.render_imgui) {
            self.imgui_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "ImGUI Pass", .{ .bUseMarker = true });

            const trazy_zone1 = ztracy.ZoneNC(@src(), "ImGUI Pass", 0x00_ff_00_00);
            defer trazy_zone1.End();

            zgui.backend.draw(cmd_list.*.mDx.pCmdList);

            profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);
        } else {
            zgui.endFrame();
        }

        // Present
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "End GPU Frame", 0x00_ff_00_00);
            defer trazy_zone1.End();

            const render_target = self.swap_chain.*.ppRenderTargets[swap_chain_image_index];

            {
                var barrier = std.mem.zeroes(graphics.RenderTargetBarrier);
                barrier.pRenderTarget = render_target;
                barrier.mCurrentState = graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
                barrier.mNewState = graphics.ResourceState.RESOURCE_STATE_PRESENT;
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, 1, &barrier);
            }

            profiler.cmdEndGpuFrameProfile(cmd_list, self.gpu_profile_token);
            graphics.endCmd(cmd_list);

            var flush_update_desc = std.mem.zeroes(resource_loader.FlushResourceUpdateDesc);
            flush_update_desc.mNodeIndex = 0;
            resource_loader.flushResourceUpdates(&flush_update_desc);

            var wait_semaphores = [2]*graphics.Semaphore{ flush_update_desc.pOutSubmittedSemaphore, self.image_acquired_semaphore };

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "Submit", 0x00_ff_00_00);
                defer trazy_zone2.End();

                var submit_desc: graphics.QueueSubmitDesc = undefined;
                submit_desc.mCmdCount = 1;
                submit_desc.mSignalSemaphoreCount = 1;
                submit_desc.mWaitSemaphoreCount = 2;
                submit_desc.ppCmds = &cmd_list;
                submit_desc.ppSignalSemaphores = &elem.semaphore;
                submit_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
                submit_desc.pSignalFence = elem.fence;
                graphics.queueSubmit(self.graphics_queue, &submit_desc);
            }

            {
                const trazy_zone2 = ztracy.ZoneNC(@src(), "Present", 0x00_ff_00_00);
                defer trazy_zone2.End();

                var queue_present_desc: graphics.QueuePresentDesc = undefined;
                queue_present_desc.mIndex = @intCast(swap_chain_image_index);
                queue_present_desc.mWaitSemaphoreCount = 1;
                queue_present_desc.pSwapChain = self.swap_chain;
                queue_present_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
                queue_present_desc.mSubmitDone = true;
                graphics.queuePresent(self.graphics_queue, &queue_present_desc);
            }
        }

        self.frame_index = (self.frame_index + 1) % Renderer.data_buffer_count;
    }

    pub fn uploadMaterial(self: *Renderer, material_data: fd.UberShader) !MaterialHandle {
        const offset = self.materials.items.len * @sizeOf(Material);

        const material = Material{
            .albedo_color = [4]f32{ material_data.base_color.r, material_data.base_color.g, material_data.base_color.b, 1.0 },
            .roughness = material_data.roughness,
            .metallic = material_data.metallic,
            .normal_intensity = material_data.normal_intensity,
            .emissive_strength = material_data.emissive_strength,
            .albedo_texture_index = self.getTextureBindlessIndex(material_data.albedo),
            .emissive_texture_index = self.getTextureBindlessIndex(material_data.emissive),
            .normal_texture_index = self.getTextureBindlessIndex(material_data.normal),
            .arm_texture_index = self.getTextureBindlessIndex(material_data.arm),
            .detail_feature = if (material_data.detail_feature) 1 else 0,
            .detail_mask_texture_index = self.getTextureBindlessIndex(material_data.detail_mask),
            .detail_baseColor_texture_index = self.getTextureBindlessIndex(material_data.detail_base_color),
            .detail_normal_texture_index = self.getTextureBindlessIndex(material_data.detail_normal),
            .detail_arm_texture_index = self.getTextureBindlessIndex(material_data.detail_arm),
            .detail_use_uv2 = if (material_data.detail_use_uv2) 1 else 0,
            .wind_feature = if (material_data.wind_feature) 1 else 0,
            .wind_initial_bend = material_data.wind_initial_bend,
            .wind_stifness = material_data.wind_stifness,
            .wind_drag = material_data.wind_drag,
            .wind_shiver_feature = if (material_data.wind_shiver_feature) 1 else 0,
            .wind_shiver_drag = material_data.wind_shiver_drag,
            .wind_normal_influence = material_data.wind_normal_influence,
            .wind_shiver_directionality = material_data.wind_shiver_directionality,
        };

        const pipeline_ids = PassPipelineIds{
            .shadow_caster_pipeline_id = material_data.shadow_caster_pipeline_id,
            .gbuffer_pipeline_id = material_data.gbuffer_pipeline_id,
        };

        self.materials.append(material) catch unreachable;

        const buffer = self.buffer_pool.getColumn(self.materials_buffer, .buffer) catch unreachable;

        var update_desc = std.mem.zeroes(resource_loader.BufferUpdateDesc);
        update_desc.pBuffer = @ptrCast(buffer);
        update_desc.mDstOffset = offset;
        update_desc.mSize = @sizeOf(Material);
        resource_loader.beginUpdateResource(&update_desc);
        util.memcpy(update_desc.pMappedData.?, &material, @sizeOf(Material));
        resource_loader.endUpdateResource(&update_desc);

        const handle: MaterialHandle = try self.material_pool.add(.{ .material = material, .buffer_offset = @intCast(offset), .pipeline_ids = pipeline_ids });
        return handle;
    }

    pub fn getMaterialPipelineIds(self: *Renderer, handle: MaterialHandle) PassPipelineIds {
        const pipeline_ids = self.material_pool.getColumn(handle, .pipeline_ids) catch unreachable;
        return pipeline_ids;
    }

    pub fn getMaterialBufferOffset(self: *Renderer, handle: MaterialHandle) u32 {
        const offset = self.material_pool.getColumn(handle, .buffer_offset) catch unreachable;
        return offset;
    }

    pub fn loadMesh(self: *Renderer, path: [:0]const u8, vertex_layout_id: IdLocal) !MeshHandle {
        const vertex_layout = self.vertex_layouts_map.get(vertex_layout_id).?;

        var mesh: Mesh = undefined;
        mesh.geometry = null;
        mesh.buffer = null;
        mesh.data = null;
        mesh.vertex_layout_id = vertex_layout_id;

        mesh.buffer_layout_desc.mSemanticBindings = std.mem.zeroes([19]u32);

        for (0..vertex_layout.mAttribCount) |i| {
            mesh.buffer_layout_desc.mSemanticBindings[@intCast(vertex_layout.mAttribs[i].mSemantic.bits)] = @intCast(i);
            mesh.buffer_layout_desc.mVerticesStrides[i] = @intCast(graphics.byteSizeOfBlock(vertex_layout.mAttribs[i].mFormat));
        }

        const index_count_max: u32 = 1024 * 1024;
        const vertex_count_max: u32 = 1024 * 1024;
        var buffer_load_desc = std.mem.zeroes(resource_loader.GeometryBufferLoadDesc);
        buffer_load_desc.mStartState = @intCast(graphics.ResourceState.RESOURCE_STATE_COPY_DEST.bits);
        buffer_load_desc.pOutGeometryBuffer = &mesh.buffer;
        buffer_load_desc.mIndicesSize = @sizeOf(u32) * index_count_max;
        buffer_load_desc.pNameIndexBuffer = "Indices";

        for (0..vertex_layout.mAttribCount) |i| {
            buffer_load_desc.mVerticesSizes[i] = mesh.buffer_layout_desc.mVerticesStrides[i] * vertex_count_max;
        }

        // TODO(gmodarelli): Figure out how to pass these debug names
        // buffer_load_desc.pNamesVertexBuffers[0] = "Positions";
        // buffer_load_desc.pNamesVertexBuffers[1] = "Normals";
        // buffer_load_desc.pNamesVertexBuffers[2] = "Tangents";
        // buffer_load_desc.pNamesVertexBuffers[3] = "UVs";
        // buffer_load_desc.pNamesVertexBuffers[4] = "Colors";
        resource_loader.addGeometryBuffer(&buffer_load_desc);

        var load_desc = std.mem.zeroes(resource_loader.GeometryLoadDesc);
        load_desc.pFileName = path;
        load_desc.pVertexLayout = &vertex_layout;
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

    pub fn getMesh(self: *Renderer, handle: MeshHandle) Mesh {
        const mesh = self.mesh_pool.getColumn(handle, .mesh) catch unreachable;
        return mesh;
    }

    pub fn createTexture(self: *Renderer, desc: graphics.TextureDesc) TextureHandle {
        var texture: [*c]graphics.Texture = null;

        var load_desc = std.mem.zeroes(resource_loader.TextureLoadDesc);
        load_desc.__union_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0);
        load_desc.__union_field1.__struct_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0.__Struct0);
        load_desc.__union_field1.__struct_field1.pDesc = @constCast(&desc);
        load_desc.ppTexture = @ptrCast(&texture);

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource__Overload2(&load_desc, &token);
        resource_loader.waitForToken(&token);

        const handle: TextureHandle = self.texture_pool.add(.{ .texture = texture }) catch unreachable;
        return handle;
    }

    pub fn loadTextureWithDesc(self: *Renderer, desc: graphics.TextureDesc, path: [:0]const u8) TextureHandle {
        var texture: [*c]graphics.Texture = null;

        var load_desc = std.mem.zeroes(resource_loader.TextureLoadDesc);
        load_desc.__union_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0);
        load_desc.__union_field1.__struct_field1 = std.mem.zeroes(resource_loader.TextureLoadDesc.__Union0.__Struct0);
        load_desc.pFileName = path;
        load_desc.__union_field1.__struct_field1.pDesc = @constCast(&desc);
        load_desc.ppTexture = @ptrCast(&texture);

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource__Overload2(&load_desc, &token);
        resource_loader.waitForToken(&token);

        const handle: TextureHandle = self.texture_pool.add(.{ .texture = texture }) catch unreachable;
        return handle;
    }

    pub fn loadTexture(self: *Renderer, path: [:0]const u8) TextureHandle {
        var desc = std.mem.zeroes(graphics.TextureDesc);
        desc.bBindless = true;
        return self.loadTextureWithDesc(desc, path);
    }

    pub fn loadTextureFromMemory(self: *Renderer, width: u32, height: u32, format: graphics.TinyImageFormat, data_slice: Slice, debug_name: [*:0]const u8) TextureHandle {
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

    pub fn getTexture(self: *Renderer, handle: TextureHandle) [*]graphics.Texture {
        const texture = self.texture_pool.getColumn(handle, .texture) catch unreachable;
        return texture;
    }

    pub fn getTextureBindlessIndex(self: *Renderer, handle: TextureHandle) u32 {
        if (handle.id == TextureHandle.nil.id) {
            return std.math.maxInt(u32);
        }

        const texture = self.texture_pool.getColumn(handle, .texture) catch unreachable;
        const bindless_index = texture.*.mDx.mDescriptors;
        return @intCast(bindless_index);
    }

    pub fn createBindlessBuffer(self: *Renderer, initial_data: Slice, debug_name: [:0]const u8) BufferHandle {
        var buffer: [*c]graphics.Buffer = null;

        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.pName = debug_name;
        load_desc.mDesc.bBindless = true;
        load_desc.mDesc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW;
        load_desc.mDesc.mFlags = graphics.BufferCreationFlags.BUFFER_CREATION_FLAG_SHADER_DEVICE_ADDRESS;
        load_desc.mDesc.mMemoryUsage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_GPU_ONLY;
        // NOTE(gmodarelli): The persistent SRV uses a R32_TYPELESS representation, so we need to provide an element count in terms of 32bit data
        load_desc.mDesc.mElementCount = @intCast(initial_data.size / @sizeOf(u32));
        load_desc.mDesc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
        load_desc.mDesc.mSize = initial_data.size;
        if (initial_data.data) |data| {
            load_desc.pData = data;
        }
        load_desc.ppBuffer = &buffer;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        const handle: BufferHandle = self.buffer_pool.add(.{ .buffer = buffer }) catch unreachable;
        return handle;
    }

    pub fn createIndexBuffer(self: *Renderer, initial_data: Slice, index_size: u32, cpu_accessible: bool, debug_name: [:0]const u8) BufferHandle {
        var buffer: [*c]graphics.Buffer = null;

        var memory_usage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_GPU_ONLY;
        if (cpu_accessible) {
            memory_usage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
        }
        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.pName = debug_name;
        load_desc.mDesc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_INDEX_BUFFER;
        load_desc.mDesc.mFlags = graphics.BufferCreationFlags.BUFFER_CREATION_FLAG_NONE;
        load_desc.mDesc.mMemoryUsage = memory_usage;
        load_desc.mDesc.mElementCount = @intCast(initial_data.size / index_size);
        load_desc.mDesc.mSize = initial_data.size;
        if (initial_data.data) |data| {
            load_desc.pData = data;
        }
        load_desc.ppBuffer = &buffer;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        const handle: BufferHandle = self.buffer_pool.add(.{ .buffer = buffer }) catch unreachable;
        return handle;
    }

    pub fn createVertexBuffer(self: *Renderer, initial_data: Slice, vertex_size: u32, cpu_accessible: bool, debug_name: [:0]const u8) BufferHandle {
        var buffer: [*c]graphics.Buffer = null;

        var memory_usage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_GPU_ONLY;
        if (cpu_accessible) {
            memory_usage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
        }
        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.pName = debug_name;
        load_desc.mDesc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_VERTEX_BUFFER;
        load_desc.mDesc.mFlags = graphics.BufferCreationFlags.BUFFER_CREATION_FLAG_NONE;
        load_desc.mDesc.mMemoryUsage = memory_usage;
        load_desc.mDesc.mElementCount = @intCast(initial_data.size / vertex_size);
        load_desc.mDesc.mSize = initial_data.size;
        if (initial_data.data) |data| {
            load_desc.pData = data;
        }
        load_desc.ppBuffer = &buffer;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        const handle: BufferHandle = self.buffer_pool.add(.{ .buffer = buffer }) catch unreachable;
        return handle;
    }

    pub fn createUniformBuffer(self: *Renderer, comptime T: type) BufferHandle {
        var buffer: [*c]graphics.Buffer = null;

        var buffer_load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        buffer_load_desc.mDesc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_UNIFORM_BUFFER;
        buffer_load_desc.mDesc.mMemoryUsage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
        buffer_load_desc.mDesc.mFlags = graphics.BufferCreationFlags.BUFFER_CREATION_FLAG_PERSISTENT_MAP_BIT;
        buffer_load_desc.mDesc.mSize = @sizeOf(T);
        buffer_load_desc.ppBuffer = &buffer;

        resource_loader.addResource(@ptrCast(&buffer_load_desc), null);
        const handle: BufferHandle = self.buffer_pool.add(.{ .buffer = buffer }) catch unreachable;
        return handle;
    }

    pub fn updateBuffer(self: *Renderer, data: Slice, comptime T: type, handle: BufferHandle) void {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        _ = T;

        var update_desc = std.mem.zeroes(resource_loader.BufferUpdateDesc);
        update_desc.pBuffer = @ptrCast(buffer);
        resource_loader.beginUpdateResource(&update_desc);
        util.memcpy(update_desc.pMappedData.?, data.data.?, data.size);
        resource_loader.endUpdateResource(&update_desc);
    }

    pub fn getBuffer(self: *Renderer, handle: BufferHandle) [*c]graphics.Buffer {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        return buffer;
    }

    pub fn getBufferBindlessIndex(self: *Renderer, handle: BufferHandle) u32 {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        const bindless_index = buffer.*.mDx.mDescriptors;
        return @intCast(bindless_index);
    }

    pub fn getPSO(self: *Renderer, id: IdLocal) [*c]graphics.Pipeline {
        const handle = self.pso_map.get(id).?;
        const pso = self.pso_pool.getColumn(handle, .pipeline) catch unreachable;
        return pso;
    }

    pub fn getRootSignature(self: *Renderer, id: IdLocal) [*c]graphics.RootSignature {
        const handle = self.pso_map.get(id).?;
        const root_signature = self.pso_pool.getColumn(handle, .root_signature) catch unreachable;
        return root_signature;
    }

    pub fn getVertexLayout(self: *Renderer, id: IdLocal) ?graphics.VertexLayout {
        return self.vertex_layouts_map.get(id);
    }

    fn addSwapchain(self: *Renderer) bool {
        const native_handle = zglfw.getWin32Window(self.window.window).?;

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
        desc.mEnableVsync = self.vsync_enabled;
        desc.mFlags = graphics.SwapChainCreationFlags.SWAP_CHAIN_CREATION_FLAG_ENABLE_FOVEATED_RENDERING_VR;
        graphics.addSwapChain(self.renderer, &desc, &self.swap_chain);

        if (self.swap_chain == null) return false;

        return true;
    }

    fn createRenderTargets(self: *Renderer) void {
        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Depth Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field3.depth = 0.0;
            rt_desc.mClearValue.__struct_field3.stencil = 0;
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.D32_SFLOAT;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = @intCast(self.window_width);
            rt_desc.mHeight = @intCast(self.window_height);
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.depth_buffer);
        }

        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Shadow Depth Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field3.depth = 0.0;
            rt_desc.mClearValue.__struct_field3.stencil = 0;
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.D32_SFLOAT;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = 2048;
            rt_desc.mHeight = 2048;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.shadow_depth_buffer);
        }

        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Base Color Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.R8G8B8A8_SRGB;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = @intCast(self.window_width);
            rt_desc.mHeight = @intCast(self.window_height);
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.gbuffer_0);
        }

        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "World Normals Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.R10G10B10A2_UNORM;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = @intCast(self.window_width);
            rt_desc.mHeight = @intCast(self.window_height);
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.gbuffer_1);
        }

        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Material Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = @intCast(self.window_width);
            rt_desc.mHeight = @intCast(self.window_height);
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.gbuffer_2);
        }

        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Scene Color Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.R16G16B16A16_SFLOAT;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = @intCast(self.window_width);
            rt_desc.mHeight = @intCast(self.window_height);
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.scene_color);
        }
    }

    fn destroyRenderTargets(self: *Renderer) void {
        graphics.removeRenderTarget(self.renderer, self.shadow_depth_buffer);
        graphics.removeRenderTarget(self.renderer, self.depth_buffer);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_0);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_1);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_2);
        graphics.removeRenderTarget(self.renderer, self.scene_color);
    }

    fn createResolutionIndependentRenderTargets(self: *Renderer) void {
        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Transmittance LUT";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = atmosphere_render_pass.transmittance_lut_format;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = atmosphere_render_pass.transmittance_texture_width;
            rt_desc.mHeight = atmosphere_render_pass.transmittance_texture_height;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.transmittance_lut);
        }
    }

    fn destroyResolutionIndependentRenderTargets(self: *Renderer) void {
        graphics.removeRenderTarget(self.renderer, self.transmittance_lut);
    }

    fn createPipelines(self: *Renderer) void {
        var rasterizer_cull_back = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_cull_back.mCullMode = graphics.CullMode.CULL_MODE_BACK;

        var rasterizer_wireframe = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_wireframe.mCullMode = graphics.CullMode.CULL_MODE_NONE;
        rasterizer_wireframe.mFillMode = graphics.FillMode.FILL_MODE_WIREFRAME;

        var rasterizer_cull_none = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_cull_none.mCullMode = graphics.CullMode.CULL_MODE_NONE;

        var depth_gequal = std.mem.zeroes(graphics.DepthStateDesc);
        depth_gequal.mDepthWrite = true;
        depth_gequal.mDepthTest = true;
        depth_gequal.mDepthFunc = graphics.CompareMode.CMP_GEQUAL;

        const pos_uv0_nor_tan_col_vertex_layout = self.vertex_layouts_map.get(IdLocal.init("pos_uv0_nor_tan_col")).?;
        const pos_uv0_nor_tan_col_uv1_vertex_layout = self.vertex_layouts_map.get(IdLocal.init("pos_uv0_nor_tan_col_uv1")).?;
        const pos_uv0_col_vertex_layout = self.vertex_layouts_map.get(IdLocal.init("pos_uv0_col")).?;
        const im3d_vertex_layout = self.vertex_layouts_map.get(IdLocal.init("im3d")).?;
        const imgui_vertex_layout = self.vertex_layouts_map.get(IdLocal.init("imgui")).?;

        // Atmosphere Scattering
        {
            // Transmittance LUT
            {
                const id = IdLocal.init("transmittance_lut");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mVert.pFileName = "screen_triangle.vert";
                shader_load_desc.mFrag.pFileName = "render_transmittance_lut.frag";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                const static_sampler_names = [_][*c]const u8{"sampler_linear_clamp"};
                var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_clamp_to_edge};

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{atmosphere_render_pass.transmittance_lut_format};

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }

            // Multi Scattering
            {
                const id = IdLocal.init("multi_scattering");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mComp.pFileName = "render_multi_scattering.comp";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                const static_sampler_names = [_][*c]const u8{"sampler_linear_clamp"};
                var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_clamp_to_edge};

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
                pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }

            // Sky Ray Marching
            {
                const id = IdLocal.init("sky_ray_marching");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mVert.pFileName = "screen_triangle.vert";
                shader_load_desc.mFrag.pFileName = "render_ray_marching.frag";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                const static_sampler_names = [_][*c]const u8{"sampler_linear_clamp"};
                var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_clamp_to_edge};

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{self.scene_color.*.mFormat};

                // Premultiply Alpha
                var blend_state_desc = std.mem.zeroes(graphics.BlendStateDesc);
                blend_state_desc.mAlphaToCoverage = false;
                blend_state_desc.mIndependentBlend = false;
                blend_state_desc.mSrcFactors[0] = graphics.BlendConstant.BC_ONE;
                blend_state_desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
                blend_state_desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
                blend_state_desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
                blend_state_desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
                blend_state_desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
                blend_state_desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
                blend_state_desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_ALL;

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }
        }

        // Skybox
        {
            const id = IdLocal.init("skybox");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "skybox.vert";
            shader_load_desc.mFrag.pFileName = "skybox.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{"bilinearRepeatSampler"};
            var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_repeat};
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{self.scene_color.*.mFormat};

            var blend_state_desc = std.mem.zeroes(graphics.BlendStateDesc);
            blend_state_desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mSrcFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_DST_ALPHA;
            blend_state_desc.mDstFactors[0] = graphics.BlendConstant.BC_DST_ALPHA;
            blend_state_desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            blend_state_desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
            blend_state_desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            blend_state_desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_0;
            blend_state_desc.mIndependentBlend = false;

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Shadows Terrain
        {
            const id = IdLocal.init("shadows_terrain");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "shadows_terrain.vert";
            shader_load_desc.mFrag.pFileName = "shadows_terrain.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Terrain
        {
            const id = IdLocal.init("terrain");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "terrain.vert";
            shader_load_desc.mFrag.pFileName = "terrain.frag";
            // shader_load_desc.mHull.pFilename = "terrain.hull";
            // shader_load_desc.mDomain.pFilename = "terrain.domain";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.gbuffer_0.*.mFormat,
                self.gbuffer_1.*.mFormat,
                self.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Shadows Lit
        {
            const id = IdLocal.init("shadows_lit");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "shadows_lit.vert";
            shader_load_desc.mFrag.pFileName = "shadows_lit_opaque.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Shadows Lit Masked
        {
            const id = IdLocal.init("shadows_lit_masked");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "shadows_lit.vert";
            shader_load_desc.mFrag.pFileName = "shadows_lit_masked.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Lit
        {
            const id = IdLocal.init("lit");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "lit.vert";
            shader_load_desc.mFrag.pFileName = "lit_opaque.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.gbuffer_0.*.mFormat,
                self.gbuffer_1.*.mFormat,
                self.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Lit Masked
        {
            const id = IdLocal.init("lit_masked");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "lit.vert";
            shader_load_desc.mFrag.pFileName = "lit_masked.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.gbuffer_0.*.mFormat,
                self.gbuffer_1.*.mFormat,
                self.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Shadows Tree
        {
            const id = IdLocal.init("shadows_tree");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "shadows_tree.vert";
            shader_load_desc.mFrag.pFileName = "shadows_tree_opaque.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Shadows Tree Masked
        {
            const id = IdLocal.init("shadows_tree_masked");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "shadows_tree.vert";
            shader_load_desc.mFrag.pFileName = "shadows_tree_masked.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Tree
        {
            const id = IdLocal.init("tree");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "tree.vert";
            shader_load_desc.mFrag.pFileName = "tree_opaque.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.gbuffer_0.*.mFormat,
                self.gbuffer_1.*.mFormat,
                self.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Tree Masked
        {
            const id = IdLocal.init("tree_masked");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "tree.vert";
            shader_load_desc.mFrag.pFileName = "tree_masked.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.gbuffer_0.*.mFormat,
                self.gbuffer_1.*.mFormat,
                self.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_gequal;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.depth_buffer.*.mFormat;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Deferred
        {
            const id = IdLocal.init("deferred");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "fullscreen.vert";
            shader_load_desc.mFrag.pFileName = "deferred_shading.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{ "bilinearRepeatSampler", "bilinearClampSampler", "pointSampler" };
            var static_samplers = [_][*c]graphics.Sampler{ self.samplers.bilinear_repeat, self.samplers.bilinear_clamp_to_edge, self.samplers.point_clamp_to_edge };
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.scene_color.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // ImGUI Pipeline
        {
            const id = IdLocal.init("imgui");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "imgui.vert";
            shader_load_desc.mFrag.pFileName = "imgui.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{"sampler0"};
            var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_repeat};
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var blend_state_desc = std.mem.zeroes(graphics.BlendStateDesc);
            blend_state_desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mSrcFactors[0] = graphics.BlendConstant.BC_SRC_ALPHA;
            blend_state_desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            blend_state_desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
            blend_state_desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            blend_state_desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            blend_state_desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_0;
            blend_state_desc.mIndependentBlend = false;

            var rasterizer_state_desc = std.mem.zeroes(graphics.RasterizerStateDesc);
            rasterizer_state_desc.mCullMode = graphics.CullMode.CULL_MODE_NONE;
            rasterizer_state_desc.mDepthBias = 0;
            rasterizer_state_desc.mSlopeScaledDepthBias = 0.0;
            rasterizer_state_desc.mFillMode = graphics.FillMode.FILL_MODE_SOLID;
            rasterizer_state_desc.mFrontFace = graphics.FrontFace.FRONT_FACE_CW;
            rasterizer_state_desc.mMultiSample = false;
            rasterizer_state_desc.mScissor = false;
            rasterizer_state_desc.mDepthClampEnable = true;

            var depth_state = std.mem.zeroes(graphics.DepthStateDesc);
            depth_state.mDepthTest = false;
            depth_state.mDepthWrite = true;
            depth_state.mDepthFunc = graphics.CompareMode.CMP_ALWAYS;
            depth_state.mStencilTest = false;
            depth_state.mStencilFrontFunc = graphics.CompareMode.CMP_ALWAYS;
            depth_state.mDepthFrontFail = graphics.StencilOp.STENCIL_OP_KEEP;
            depth_state.mStencilFrontFail = graphics.StencilOp.STENCIL_OP_KEEP;
            depth_state.mStencilFrontPass = graphics.StencilOp.STENCIL_OP_KEEP;

            var render_targets = [_]graphics.TinyImageFormat{
                self.swap_chain.*.ppRenderTargets[0].*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&imgui_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // Im3d Pipelines
        {
            var blend_state_desc = std.mem.zeroes(graphics.BlendStateDesc);
            blend_state_desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mSrcFactors[0] = graphics.BlendConstant.BC_SRC_ALPHA;
            blend_state_desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            blend_state_desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            blend_state_desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            blend_state_desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            blend_state_desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_0;
            blend_state_desc.mIndependentBlend = false;

            var rasterizer_state_desc = std.mem.zeroes(graphics.RasterizerStateDesc);
            rasterizer_state_desc.mCullMode = graphics.CullMode.CULL_MODE_NONE;
            rasterizer_state_desc.mFillMode = graphics.FillMode.FILL_MODE_SOLID;

            var depth_state = std.mem.zeroes(graphics.DepthStateDesc);
            depth_state.mDepthWrite = false;
            depth_state.mDepthTest = false;

            // Points
            {
                const id = IdLocal.init("im3d_points");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mVert.pFileName = "im3d_points_lines.vert";
                shader_load_desc.mGeom.pFileName = "im3d_points.geom";
                shader_load_desc.mFrag.pFileName = "im3d_points.frag";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_POINT_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
                pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&im3d_vertex_layout);
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }

            // Lines
            {
                const id = IdLocal.init("im3d_lines");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mVert.pFileName = "im3d_points_lines.vert";
                shader_load_desc.mGeom.pFileName = "im3d_lines.geom";
                shader_load_desc.mFrag.pFileName = "im3d_lines.frag";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_LINE_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
                pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&im3d_vertex_layout);
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }

            // Triangles
            {
                const id = IdLocal.init("im3d_triangles");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mVert.pFileName = "im3d_triangles.vert";
                shader_load_desc.mFrag.pFileName = "im3d_triangles.frag";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
                pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&im3d_vertex_layout);
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }
        }

        // Tonemapper
        {
            const id = IdLocal.init("tonemapper");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "fullscreen.vert";
            shader_load_desc.mFrag.pFileName = "tonemapper.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{"bilinearClampSampler"};
            var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_clamp_to_edge};
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.swap_chain.*.ppRenderTargets[0].*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // UI
        {
            const id = IdLocal.init("ui");
            var shader: [*c]graphics.Shader = null;
            var root_signature: [*c]graphics.RootSignature = null;
            var pipeline: [*c]graphics.Pipeline = null;

            var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
            shader_load_desc.mVert.pFileName = "ui.vert";
            shader_load_desc.mFrag.pFileName = "ui.frag";
            resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

            const static_sampler_names = [_][*c]const u8{"bilinearRepeatSampler"};
            var static_samplers = [_][*c]graphics.Sampler{self.samplers.bilinear_repeat};
            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.swap_chain.*.ppRenderTargets[0].*.mFormat,
            };

            var blend_state_desc = std.mem.zeroes(graphics.BlendStateDesc);
            blend_state_desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            blend_state_desc.mSrcFactors[0] = graphics.BlendConstant.BC_SRC_ALPHA;
            blend_state_desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            blend_state_desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            blend_state_desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            blend_state_desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            blend_state_desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_0;
            blend_state_desc.mIndependentBlend = false;

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = null;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
            graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // IBL Pipelines
        {
            // BRDF Integration
            {
                const id = IdLocal.init("brdf_integration");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mComp.pFileName = "brdf_integration.comp";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                const static_sampler_names = [_][*c]const u8{"skyboxSampler"};
                var static_samplers = [_][*c]graphics.Sampler{self.samplers.skybox};
                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
                pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }

            // Compute Irradiance Map
            {
                const id = IdLocal.init("compute_irradiance_map");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mComp.pFileName = "compute_irradiance_map.comp";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                const static_sampler_names = [_][*c]const u8{"skyboxSampler"};
                var static_samplers = [_][*c]graphics.Sampler{self.samplers.skybox};
                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
                pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }

            // Compute Specular Map
            {
                const id = IdLocal.init("compute_specular_map");
                var shader: [*c]graphics.Shader = null;
                var root_signature: [*c]graphics.RootSignature = null;
                var pipeline: [*c]graphics.Pipeline = null;

                var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
                shader_load_desc.mComp.pFileName = "compute_specular_map.comp";
                resource_loader.addShader(self.renderer, &shader_load_desc, &shader);

                const static_sampler_names = [_][*c]const u8{"skyboxSampler"};
                var static_samplers = [_][*c]graphics.Sampler{self.samplers.skybox};
                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
                pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
                graphics.addPipeline(self.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }
        }
    }

    fn destroyPipelines(self: *Renderer) void {
        self.destroyPipeline(IdLocal.init("skybox"));
        self.destroyPipeline(IdLocal.init("terrain"));
        self.destroyPipeline(IdLocal.init("lit"));
        self.destroyPipeline(IdLocal.init("lit_masked"));
        self.destroyPipeline(IdLocal.init("deferred"));
        self.destroyPipeline(IdLocal.init("tonemapper"));
        self.destroyPipeline(IdLocal.init("ui"));
        self.destroyPipeline(IdLocal.init("brdf_integration"));
        self.destroyPipeline(IdLocal.init("compute_irradiance_map"));
        self.destroyPipeline(IdLocal.init("compute_specular_map"));
    }

    fn destroyPipeline(self: *Renderer, id: IdLocal) void {
        const handle = self.pso_map.get(id).?;
        const shader = self.pso_pool.getColumn(handle, .shader) catch unreachable;
        const root_signature = self.pso_pool.getColumn(handle, .root_signature) catch unreachable;
        const pipeline = self.pso_pool.getColumn(handle, .pipeline) catch unreachable;
        graphics.removePipeline(self.renderer, pipeline);
        graphics.removeRootSignature(self.renderer, root_signature);
        graphics.removeShader(self.renderer, shader);
        self.pso_pool.remove(handle) catch unreachable;
    }
};

const StaticSamplers = struct {
    bilinear_repeat: [*c]graphics.Sampler = null,
    bilinear_clamp_to_edge: [*c]graphics.Sampler = null,
    point_repeat: [*c]graphics.Sampler = null,
    point_clamp_to_edge: [*c]graphics.Sampler = null,
    point_clamp_to_border: [*c]graphics.Sampler = null,
    skybox: [*c]graphics.Sampler = null,

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

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;
            desc.mMaxAnisotropy = 16.0;
            graphics.addSampler(renderer, &desc, &static_samplers.skybox);
        }

        return static_samplers;
    }

    pub fn exit(self: *StaticSamplers, renderer: [*c]graphics.Renderer) void {
        graphics.removeSampler(renderer, self.bilinear_repeat);
        graphics.removeSampler(renderer, self.bilinear_clamp_to_edge);
        graphics.removeSampler(renderer, self.point_repeat);
        graphics.removeSampler(renderer, self.point_clamp_to_edge);
        graphics.removeSampler(renderer, self.point_clamp_to_border);
        graphics.removeSampler(renderer, self.skybox);
    }
};

pub const Mesh = struct {
    geometry: [*c]resource_loader.Geometry,
    data: [*c]resource_loader.GeometryData,
    buffer: [*c]resource_loader.GeometryBuffer,
    buffer_layout_desc: resource_loader.GeometryBufferLayoutDesc,
    vertex_layout_id: IdLocal,
    loaded: bool,
};

pub const Material = struct {
    albedo_color: [4]f32,
    roughness: f32,
    metallic: f32,
    normal_intensity: f32,
    emissive_strength: f32,
    albedo_texture_index: u32,
    emissive_texture_index: u32,
    normal_texture_index: u32,
    arm_texture_index: u32,
    detail_feature: u32,
    detail_mask_texture_index: u32,
    detail_baseColor_texture_index: u32,
    detail_normal_texture_index: u32,
    detail_arm_texture_index: u32,
    detail_use_uv2: u32,
    wind_feature: u32,
    wind_initial_bend: f32,
    wind_stifness: f32,
    wind_drag: f32,
    wind_shiver_feature: u32,
    wind_shiver_drag: f32,
    wind_normal_influence: f32,
    wind_shiver_directionality: f32,
};

pub const PassPipelineIds = struct {
    shadow_caster_pipeline_id: ?IdLocal,
    gbuffer_pipeline_id: ?IdLocal,
};

const MaterialPool = Pool(16, 16, Material, struct { material: Material, buffer_offset: u32, pipeline_ids: PassPipelineIds });
pub const MaterialHandle = MaterialPool.Handle;

const MeshPool = Pool(16, 16, Mesh, struct { mesh: Mesh });
pub const MeshHandle = MeshPool.Handle;

const TexturePool = Pool(16, 16, graphics.Texture, struct { texture: [*c]graphics.Texture });
pub const TextureHandle = TexturePool.Handle;

const BufferPool = Pool(16, 16, graphics.Buffer, struct { buffer: [*c]graphics.Buffer });
pub const BufferHandle = BufferPool.Handle;

const PSOPool = Pool(16, 16, graphics.Shader, struct { shader: [*c]graphics.Shader, root_signature: [*c]graphics.RootSignature, pipeline: [*c]graphics.Pipeline });
const PSOHandle = PSOPool.Handle;
const PSOMap = std.AutoHashMap(IdLocal, PSOHandle);

pub const Slice = extern struct {
    data: ?*const anyopaque,
    size: u64,
};

pub const sub_mesh_max_count: u32 = 32;

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
