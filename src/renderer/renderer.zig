const std = @import("std");

const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const renderer_types = @import("types.zig");
const zforge = @import("zforge");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const geometry = @import("geometry.zig");

const file_system = zforge.file_system;
const font = zforge.font;
const graphics = zforge.graphics;
const log = zforge.log;
const memory = zforge.memory;
const pso = @import("pso.zig");
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
pub const renderPassCreateDescriptorSetsFn = ?*const fn (user_data: *anyopaque) void;
pub const renderPassPrepareDescriptorSetsFn = ?*const fn (user_data: *anyopaque) void;
pub const renderPassUnloadDescriptorSetsFn = ?*const fn (user_data: *anyopaque) void;

pub const brdf_lut_texture_size: u32 = 512;
pub const irradiance_texture_size: u32 = 32;
pub const specular_texture_size: u32 = 128;
pub const specular_texture_mips: u32 = std.math.log2(specular_texture_size) + 1;

pub const RenderPass = struct {
    render_ssao_pass_fn: renderPassRenderFn = null,
    render_shadow_pass_fn: renderPassRenderFn = null,
    render_gbuffer_pass_fn: renderPassRenderFn = null,
    render_deferred_pass_fn: renderPassRenderFn = null,
    render_atmosphere_pass_fn: renderPassRenderFn = null,
    render_water_pass_fn: renderPassRenderFn = null,
    render_post_processing_pass_fn: renderPassRenderFn = null,
    render_ui_pass_fn: renderPassRenderFn = null,

    render_imgui_fn: renderPassImGuiFn = null,

    create_descriptor_sets_fn: renderPassCreateDescriptorSetsFn = null,
    prepare_descriptor_sets_fn: renderPassPrepareDescriptorSetsFn = null,
    unload_descriptor_sets_fn: renderPassUnloadDescriptorSetsFn = null,

    user_data: *anyopaque,
};

pub const opaque_pipelines = pso.opaque_pipelines;
pub const cutout_pipelines = pso.cutout_pipelines;
const hdr_format = graphics.TinyImageFormat.R16G16B16A16_SFLOAT; // B10G11R11_UFLOAT

const VertexLayoutHashMap = std.AutoHashMap(IdLocal, graphics.VertexLayout);

const BuffersVisualizationPushConstants = struct {
    buffer_visualization_mode: u32,
};

const visualization_modes = [_][:0]const u8{
    "Albedo",
    "World Normal",
    "Occlusion",
    "Roughness",
    "Metalness",
    "Reflectance",
};

pub const Renderer = struct {
    pub const data_buffer_count: u32 = 2;

    allocator: std.mem.Allocator = undefined,
    renderer: [*c]graphics.Renderer = null,
    window: *window.Window = undefined,
    window_width: i32 = 0,
    window_height: i32 = 0,
    time: f64 = 0.0,
    vsync_enabled: bool = true,
    ibl_enabled: bool = true,

    swap_chain: [*c]graphics.SwapChain = null,
    gpu_cmd_ring: graphics.GpuCmdRing = undefined,
    image_acquired_semaphore: [*c]graphics.Semaphore = null,
    swap_chain_image_index: u32 = 0,
    graphics_queue: [*c]graphics.Queue = null,
    frame_index: u32 = 0,

    gpu_profile_token: profiler.ProfileToken = undefined,
    ssao_pass_profile_token: profiler.ProfileToken = undefined,
    z_prepass_pass_profile_token: profiler.ProfileToken = undefined,
    shadow_pass_profile_token: profiler.ProfileToken = undefined,
    gbuffer_pass_profile_token: profiler.ProfileToken = undefined,
    deferred_pass_profile_token: profiler.ProfileToken = undefined,
    atmosphere_pass_profile_token: profiler.ProfileToken = undefined,
    water_pass_profile_token: profiler.ProfileToken = undefined,
    post_processing_pass_profile_token: profiler.ProfileToken = undefined,
    ui_pass_profile_token: profiler.ProfileToken = undefined,
    imgui_pass_profile_token: profiler.ProfileToken = undefined,
    composite_sdr_profile_token: profiler.ProfileToken = undefined,

    // Geometry Buffers
    // ================
    // Vertex Buffer
    vertex_buffer_mutex: std.Thread.Mutex = undefined,
    vertex_buffer: BufferHandle = undefined,
    vertex_buffer_size: u64 = 0,
    vertex_buffer_offset: u64 = 0,
    vertex_count: u32 = 0,
    // Index Buffer
    index_buffer_mutex: std.Thread.Mutex = undefined,
    index_buffer: BufferHandle = undefined,
    index_buffer_size: u64 = 0,
    index_buffer_offset: u64 = 0,
    index_count: u32 = 0,

    // Render Targets
    // ==============
    // Depth
    depth_buffer: [*c]graphics.RenderTarget = null,
    depth_buffer_copy: [*c]graphics.RenderTarget = null,
    linear_depth_buffers: [2]TextureHandle = .{ undefined, undefined },

    // Shadows
    shadow_depth_buffer: [*c]graphics.RenderTarget = null,

    // GBuffer
    gbuffer_0: [*c]graphics.RenderTarget = null,
    gbuffer_1: [*c]graphics.RenderTarget = null,
    gbuffer_2: [*c]graphics.RenderTarget = null,

    // Lighting
    scene_color: [*c]graphics.RenderTarget = null,
    scene_color_copy: [*c]graphics.RenderTarget = null,

    // UI
    ui_overlay: [*c]graphics.RenderTarget = null,

    // IBL Textures
    brdf_lut_texture: TextureHandle = undefined,
    irradiance_texture: TextureHandle = undefined,
    specular_texture: TextureHandle = undefined,

    // Bloom Render Targets
    bloom_width: u32 = 0,
    bloom_height: u32 = 0,
    bloom_uav1: [2]TextureHandle = .{ undefined, undefined },
    bloom_uav2: [2]TextureHandle = .{ undefined, undefined },
    bloom_uav3: [2]TextureHandle = .{ undefined, undefined },
    bloom_uav4: [2]TextureHandle = .{ undefined, undefined },
    bloom_uav5: [2]TextureHandle = .{ undefined, undefined },
    luma_lr: TextureHandle = undefined,
    luminance: TextureHandle = undefined,

    vertex_layouts_map: VertexLayoutHashMap = undefined,
    roboto_font_id: u32 = 0,

    material_pool: MaterialPool = undefined,
    materials: std.ArrayList(Material) = undefined,
    materials_buffer: BufferHandle = undefined,

    mesh_pool: MeshPool = undefined,
    legacy_mesh_pool: LegacyMeshPool = undefined,
    texture_pool: TexturePool = undefined,
    buffer_pool: BufferPool = undefined,
    pso_manager: pso.PSOManager = undefined,

    render_passes: std.ArrayList(*RenderPass) = undefined,
    render_imgui: bool = false,

    // Buffers Visualization
    // =====================
    selected_visualization_mode: i32 = -1,
    buffers_visualization_descriptor_set: [*c]graphics.DescriptorSet = undefined,

    // Composite SDR Pass
    // ==================
    composite_sdr_pass_descriptor_set: [*c]graphics.DescriptorSet = undefined,

    pub const Error = error{
        NotInitialized,
        SwapChainNotInitialized,
        FontSystemNotInitialized,
        MemorySystemNotInitialized,
        FileSystemNotInitialized,
    };

    pub fn init(self: *Renderer, wnd: *window.Window, allocator: std.mem.Allocator) Error!void {
        self.allocator = allocator;

        self.window = wnd;
        self.window_width = wnd.frame_buffer_size[0];
        self.window_height = wnd.frame_buffer_size[1];
        self.time = 0.0;
        self.vsync_enabled = true;
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

        // var profiler_desc = profiler.ProfilerDesc{};
        // profiler_desc.pRenderer = self.renderer;
        // profiler.initProfiler(&profiler_desc);
        // self.gpu_profile_token = profiler.initGpuProfiler(self.renderer, self.graphics_queue, "Graphics");

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
            vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
            vertex_layout.mAttribs[1].mBinding = 1;
            vertex_layout.mAttribs[1].mLocation = 1;
            vertex_layout.mAttribs[1].mOffset = 0;
            vertex_layout.mAttribs[2].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
            vertex_layout.mAttribs[2].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
            vertex_layout.mAttribs[2].mBinding = 2;
            vertex_layout.mAttribs[2].mLocation = 2;
            vertex_layout.mAttribs[2].mOffset = 0;
            self.vertex_layouts_map.put(IdLocal.init("pos_uv0_col"), vertex_layout) catch unreachable;

            vertex_layout.mBindingCount = 4;
            vertex_layout.mAttribCount = 4;
            vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
            vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
            vertex_layout.mAttribs[0].mBinding = 0;
            vertex_layout.mAttribs[0].mLocation = 0;
            vertex_layout.mAttribs[0].mOffset = 0;
            vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_NORMAL;
            vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
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
            vertex_layout.mAttribs[3].mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
            vertex_layout.mAttribs[3].mBinding = 3;
            vertex_layout.mAttribs[3].mLocation = 3;
            vertex_layout.mAttribs[3].mOffset = 0;
            self.vertex_layouts_map.put(IdLocal.init("pos_uv0_nor_tan"), vertex_layout) catch unreachable;

            vertex_layout.mBindingCount = 5;
            vertex_layout.mAttribCount = 5;
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
        self.legacy_mesh_pool = LegacyMeshPool.initMaxCapacity(allocator) catch unreachable;
        self.texture_pool = TexturePool.initMaxCapacity(allocator) catch unreachable;
        self.buffer_pool = BufferPool.initMaxCapacity(allocator) catch unreachable;
        self.pso_manager = pso.PSOManager{};
        self.pso_manager.init(self, allocator) catch unreachable;

        self.material_pool = MaterialPool.initMaxCapacity(allocator) catch unreachable;
        self.materials = std.ArrayList(Material).init(allocator);
        const buffer_data = Slice{
            .data = null,
            .size = 1000 * @sizeOf(Material),
        };
        self.materials_buffer = self.createBindlessBuffer(buffer_data, "Materials Buffer");

        self.createIBLTextures();

        self.render_passes = std.ArrayList(*RenderPass).init(allocator);

        zgui.init(allocator);
        _ = zgui.io.addFontFromFile("content/fonts/Roboto-Medium.ttf", 16.0);

        // Geometry Buffers
        {
            self.index_buffer_mutex = std.Thread.Mutex{};
            self.index_buffer_size = 8 * 1024 * 1024 * @sizeOf(u32);
            self.index_buffer_offset = 0;
            self.index_count = 0;

            const index_buffer_data = Slice{
                .data = null,
                .size = self.index_buffer_size,
            };
            self.index_buffer = self.createIndexBuffer(index_buffer_data, @sizeOf(u32), false, "Index Buffer");

            self.vertex_buffer_mutex = std.Thread.Mutex{};
            self.vertex_buffer_size = 8 * 1024 * 1024 * @sizeOf(geometry.Vertex);
            self.vertex_buffer_offset = 0;
            self.vertex_count = 0;

            const vertex_buffer_data = Slice{
                .data = null,
                .size = self.vertex_buffer_size,
            };
            self.vertex_buffer = self.createBindlessBuffer(vertex_buffer_data, "Vertex Buffer");
        }

        // TESTING NEW MESH LOADING
        {
            _ = self.loadMesh("content/prefabs/environment/beech/beech_tree_04_LOD0.mesh") catch unreachable;
        }
    }

    pub fn exit(self: *Renderer) void {
        self.pso_manager.exit();

        graphics.removeDescriptorSet(self.renderer, self.composite_sdr_pass_descriptor_set);
        graphics.removeDescriptorSet(self.renderer, self.buffers_visualization_descriptor_set);

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
            // TODO
            _ = mesh;
        }
        self.mesh_pool.deinit();

        var legacy_mesh_handles = self.legacy_mesh_pool.liveHandles();
        while (legacy_mesh_handles.next()) |handle| {
            const mesh = self.legacy_mesh_pool.getColumn(handle, .mesh) catch unreachable;
            resource_loader.removeResource__Overload3(mesh.geometry);
            resource_loader.removeResource__Overload4(mesh.data);
        }
        self.legacy_mesh_pool.deinit();

        // TODO(juice): Clean gpu resources
        self.material_pool.deinit();
        self.materials.deinit();

        self.render_passes.deinit();

        self.vertex_layouts_map.deinit();

        graphics.exitQueue(self.renderer, self.graphics_queue);
        self.gpu_cmd_ring.destroy(self.renderer);
        graphics.exitSemaphore(self.renderer, self.image_acquired_semaphore);

        // profiler.exitGpuProfiler(self.gpu_profile_token);
        // profiler.exitProfiler();

        self.destroyResolutionIndependentRenderTargets();

        font.exitFontSystem();
        resource_loader.exitResourceLoaderInterface(self.renderer);
        graphics.exitRenderer(self.renderer);

        font.platformExitFontSystem();
        log.exitLog();
        file_system.exitFileSystem();
    }

    pub fn registerRenderPass(self: *Renderer, render_pass: *RenderPass) void {
        self.render_passes.append(render_pass) catch unreachable;
    }

    pub fn unregisterRenderPass(self: *Renderer, render_pass: *RenderPass) void {
        var render_pass_index: usize = self.render_passes.items.len;

        for (self.render_passes.items, 0..) |rp, i| {
            if (rp == render_pass) {
                render_pass_index = i;
            }
        }

        if (render_pass_index < self.render_passes.items.len) {
            _ = self.render_passes.orderedRemove(render_pass_index);
        }
    }

    pub fn onLoad(self: *Renderer, reload_desc: graphics.ReloadDesc) Error!void {
        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            if (!self.addSwapchain()) {
                return Error.SwapChainNotInitialized;
            }

            self.createRenderTargets();
        }

        if (reload_desc.mType.SHADER) {
            self.pso_manager.createPipelines();

            const rtv_format = self.swap_chain.*.ppRenderTargets[0].*.mFormat;
            const dsv_format = self.depth_buffer.*.mFormat;
            const pipeline_id = IdLocal.init("imgui");
            const pipeline = self.pso_manager.getPipeline(pipeline_id);
            const root_signature = self.pso_manager.getRootSignature(pipeline_id);
            const heap = self.renderer.*.mDx.pCbvSrvUavHeaps[0].pHeap;
            const cpu_desc_handle = self.renderer.*.mDx.pCbvSrvUavHeaps[0].mStartCpuHandle;
            const gpu_desc_handle = self.renderer.*.mDx.pCbvSrvUavHeaps[0].mStartGpuHandle;

            const zgui_init_data: zgui.backend.ImGui_ImplDX12_InitInfo = .{
                // self.window.window,
                .command_queue = self.graphics_queue.*.mDx.pQueue,
                .device = self.renderer.*.mDx.pDevice,
                .num_frames_in_flight = data_buffer_count,
                .rtv_format = @intFromEnum(rtv_format),
                .dsv_format = @intFromEnum(dsv_format),
                .cbv_srv_heap = heap,
                .root_signature = root_signature.*.mDx.pRootSignature,
                .pipeline_state = pipeline.*.mDx.__union_field1.pPipelineState,
                .font_srv_cpu_desc_handle = @as(zgui.backend.D3D12_CPU_DESCRIPTOR_HANDLE, @bitCast(cpu_desc_handle)),
                .font_srv_gpu_desc_handle = @as(zgui.backend.D3D12_GPU_DESCRIPTOR_HANDLE, @bitCast(gpu_desc_handle)),
            };

            zgui.backend.init(self.window.window, zgui_init_data);

            self.createCompositeSDRDescriptorSet();
            self.createBuffersVisualizationDescriptorSet();

            for (self.render_passes.items) |render_pass| {
                if (render_pass.create_descriptor_sets_fn) |create_descriptor_sets_fn| {
                    create_descriptor_sets_fn(render_pass.user_data);
                }
            }
        }

        self.prepareCompositeSDRDescriptorSet();
        self.prepareBuffersVisualizationDescriptorSet();

        for (self.render_passes.items) |render_pass| {
            if (render_pass.prepare_descriptor_sets_fn) |prepare_descriptor_sets_fn| {
                prepare_descriptor_sets_fn(render_pass.user_data);
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

        if (reload_desc.mType.SHADER) {
            self.pso_manager.destroyPipelines();
            zgui.backend.deinit();
        }

        if (reload_desc.mType.RESIZE or reload_desc.mType.RENDERTARGET) {
            graphics.removeSwapChain(self.renderer, self.swap_chain);
            self.destroyRenderTargets();
        }

        if (reload_desc.mType.SHADER) {
            for (self.render_passes.items) |render_pass| {
                if (render_pass.unload_descriptor_sets_fn) |unload_descriptor_sets_fn| {
                    unload_descriptor_sets_fn(render_pass.user_data);
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
                        // zgui.text("GPU Average time: {d}", .{profiler.getGpuProfileAvgTime(self.gpu_profile_token)});

                        // zgui.text("\tZ PrePass: {d}", .{profiler.getGpuProfileAvgTime(self.z_prepass_pass_profile_token)});
                        // zgui.text("\tShadow Map Pass: {d}", .{profiler.getGpuProfileAvgTime(self.shadow_pass_profile_token)});
                        // zgui.text("\tGBuffer Pass: {d}", .{profiler.getGpuProfileAvgTime(self.gbuffer_pass_profile_token)});
                        // zgui.text("\tDeferred Shading Pass: {d}", .{profiler.getGpuProfileAvgTime(self.deferred_pass_profile_token)});
                        // zgui.text("\tAtmosphere Pass: {d}", .{profiler.getGpuProfileAvgTime(self.atmosphere_pass_profile_token)});
                        // zgui.text("\tWater Pass: {d}", .{profiler.getGpuProfileAvgTime(self.water_pass_profile_token)});
                        // zgui.text("\tPost Processing Pass: {d}", .{profiler.getGpuProfileAvgTime(self.post_processing_pass_profile_token)});
                        // zgui.text("\tUI Pass: {d}", .{profiler.getGpuProfileAvgTime(self.ui_pass_profile_token)});
                        // zgui.text("\tImGUI Pass: {d}", .{profiler.getGpuProfileAvgTime(self.imgui_pass_profile_token)});
                        // zgui.text("\tComposite SDR Pass: {d}", .{profiler.getGpuProfileAvgTime(self.composite_sdr_profile_token)});
                    }
                }

                // Renderer Settings
                {
                    if (zgui.collapsingHeader("Renderer", .{ .default_open = true })) {
                        _ = zgui.checkbox("VSync", .{ .v = &self.vsync_enabled });
                        _ = zgui.checkbox("IBL", .{ .v = &self.ibl_enabled });

                        if (zgui.button("Visualization Mode", .{})) {
                            zgui.openPopup("viz_mode_popup", zgui.PopupFlags.any_popup);
                        }
                        zgui.sameLine(.{});
                        zgui.textUnformatted(if (self.selected_visualization_mode == -1) "<None>" else visualization_modes[@intCast(self.selected_visualization_mode)]);
                        if (zgui.beginPopup("viz_mode_popup", .{})) {
                            if (zgui.selectable("None", .{})) {
                                self.selected_visualization_mode = -1;
                            }
                            for (visualization_modes, 0..) |mode, index| {
                                if (zgui.selectable(mode, .{})) {
                                    self.selected_visualization_mode = @intCast(index);
                                }
                            }
                            zgui.endPopup();
                        }
                        // _ = zgui.checkbox("Post Processing", .{ .v = &self.pp_enabled });
                    }
                }

                for (self.render_passes.items) |render_pass| {
                    if (render_pass.render_imgui_fn) |render_imgui_fn| {
                        render_imgui_fn(render_pass.user_data);
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

        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Acquire Next Image", 0x00_ff_00_00);
            defer trazy_zone1.End();
            graphics.acquireNextImage(self.renderer, self.swap_chain, self.image_acquired_semaphore, null, &self.swap_chain_image_index);
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

        // profiler.cmdBeginGpuFrameProfile(cmd_list, self.gpu_profile_token, .{ .bUseMarker = true });

        // SSAO
        if (false) {
            // self.ssao_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "SSAO", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "SSAO", 0x00_ff_00_00);
            defer trazy_zone1.End();

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_ssao_pass_fn) |render_ssao_pass_fn| {
                    render_ssao_pass_fn(cmd_list, render_pass.user_data);
                    // NOTE: There musto be only one render_pass that renders SSAO. This abstraction
                    // has already reached its breaking point :D
                    break;
                }
            }
        }

        // Shadow Map Pass
        {
            // self.shadow_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Shadow Map Pass", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

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

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_shadow_pass_fn) |render_shadow_pass_fn| {
                    render_shadow_pass_fn(cmd_list, render_pass.user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // GBuffer Pass
        {
            // self.gbuffer_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "GBuffer Pass", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

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

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_gbuffer_pass_fn) |render_gbuffer_pass_fn| {
                    render_gbuffer_pass_fn(cmd_list, render_pass.user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Deferred Shading
        {
            // self.deferred_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Deferred Shading", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

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

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_deferred_pass_fn) |render_deferred_pass_fn| {
                    render_deferred_pass_fn(cmd_list, render_pass.user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Atmospheric Scattering Pass
        {
            // self.atmosphere_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Atmosphere", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Atmosphere", 0x00_ff_00_00);
            defer trazy_zone1.End();

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_atmosphere_pass_fn) |render_atmosphere_pass_fn| {
                    render_atmosphere_pass_fn(cmd_list, render_pass.user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Water Pass
        {
            // self.water_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Water", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Water", 0x00_ff_00_00);
            defer trazy_zone1.End();

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_water_pass_fn) |render_water_pass_fn| {
                    render_water_pass_fn(cmd_list, render_pass.user_data);
                }
            }

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Post Processing
        {
            // self.post_processing_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Post Processing", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Post Processing", 0x00_ff_00_00);
            defer trazy_zone1.End();

            for (self.render_passes.items) |render_pass| {
                if (render_pass.render_post_processing_pass_fn) |render_post_processing_pass_fn| {
                    render_post_processing_pass_fn(cmd_list, render_pass.user_data);
                }
            }
        }

        // UI Overlay
        {
            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.ui_overlay, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.ui_overlay;
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            // UI Pass
            {
                // self.ui_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "UI Pass", .{ .bUseMarker = true });
                // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

                const trazy_zone1 = ztracy.ZoneNC(@src(), "UI Pass", 0x00_ff_00_00);
                defer trazy_zone1.End();

                for (self.render_passes.items) |render_pass| {
                    if (render_pass.render_ui_pass_fn) |render_ui_pass_fn| {
                        render_ui_pass_fn(cmd_list, render_pass.user_data);
                    }
                }
            }

            // ImGUI Pass
            if (self.render_imgui) {
                // self.imgui_pass_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "ImGUI Pass", .{ .bUseMarker = true });
                // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

                const trazy_zone1 = ztracy.ZoneNC(@src(), "ImGUI Pass", 0x00_ff_00_00);
                defer trazy_zone1.End();

                zgui.backend.draw(cmd_list.*.mDx.pCmdList);
            } else {
                zgui.endFrame();
            }

            var output_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.ui_overlay, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET, graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Composite SDR
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Composite SDR", 0x00_ff_00_00);
            defer trazy_zone1.End();

            // self.composite_sdr_profile_token = profiler.cmdBeginGpuTimestampQuery(cmd_list, self.gpu_profile_token, "Composite SDR", .{ .bUseMarker = true });
            // defer profiler.cmdEndGpuTimestampQuery(cmd_list, self.gpu_profile_token);

            const render_target = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(render_target, graphics.ResourceState.RESOURCE_STATE_PRESENT, graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET),
            };

            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            const pipeline_id = IdLocal.init("composite_sdr");
            const pipeline = self.getPSO(pipeline_id);

            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.composite_sdr_pass_descriptor_set);
            graphics.cmdDraw(cmd_list, 3, 0);
        }

        // Debug Viz
        if (self.selected_visualization_mode >= 0) {
            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            const pipeline_id = IdLocal.init("buffer_visualizer");
            const root_signature = self.getRootSignature(pipeline_id);
            const pipeline = self.getPSO(pipeline_id);

            const root_constant_index = graphics.getDescriptorIndexFromName(root_signature, "RootConstant");
            std.debug.assert(root_constant_index != renderer_types.InvalidResourceIndex);

            const push_constants = BuffersVisualizationPushConstants{
                .buffer_visualization_mode = @intCast(self.selected_visualization_mode),
            };

            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.buffers_visualization_descriptor_set);
            graphics.cmdBindPushConstants(cmd_list, root_signature, root_constant_index, @constCast(&push_constants));
            graphics.cmdDraw(cmd_list, 3, 0);
        }

        // Present
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "End GPU Frame", 0x00_ff_00_00);
            defer trazy_zone1.End();

            const render_target = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];

            {
                var barrier = std.mem.zeroes(graphics.RenderTargetBarrier);
                barrier.pRenderTarget = render_target;
                barrier.mCurrentState = graphics.ResourceState.RESOURCE_STATE_RENDER_TARGET;
                barrier.mNewState = graphics.ResourceState.RESOURCE_STATE_PRESENT;
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, 1, &barrier);
            }

            // profiler.cmdEndGpuFrameProfile(cmd_list, self.gpu_profile_token);
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
                queue_present_desc.mIndex = @intCast(self.swap_chain_image_index);
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
            .uv_tiling_offset = [4]f32{ material_data.uv_tiling_offset[0], material_data.uv_tiling_offset[1], material_data.uv_tiling_offset[2], material_data.uv_tiling_offset[3] },
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

        const handle: MaterialHandle = try self.material_pool.add(.{
            .material = material,
            .buffer_offset = @intCast(offset),
            .pipeline_ids = pipeline_ids,
            .alpha_test = material_data.alpha_test,
        });
        return handle;
    }

    pub fn getMaterialAlphaTest(self: *Renderer, handle: MaterialHandle) bool {
        const alpha_test = self.material_pool.getColumn(handle, .alpha_test) catch unreachable;
        return alpha_test;
    }

    pub fn getMaterialPipelineIds(self: *Renderer, handle: MaterialHandle) PassPipelineIds {
        const pipeline_ids = self.material_pool.getColumn(handle, .pipeline_ids) catch unreachable;
        return pipeline_ids;
    }

    pub fn getMaterialBufferOffset(self: *Renderer, handle: MaterialHandle) u32 {
        const offset = self.material_pool.getColumn(handle, .buffer_offset) catch unreachable;
        return offset;
    }

    pub fn loadMesh(self: *Renderer, path: []const u8) !MeshHandle {
        var mesh_data = std.ArrayList(geometry.MeshData).init(self.allocator);
        defer mesh_data.deinit();

        var load_desc: geometry.MeshLoadDesc = undefined;
        load_desc.mesh_path = path;
        load_desc.allocator = self.allocator;
        load_desc.mesh_data = &mesh_data;
        geometry.loadMesh(&load_desc);

        var mesh: geometry.Mesh = undefined;
        mesh.sub_mesh_count = @intCast(mesh_data.items.len);

        for (mesh_data.items, 0..) |md, sub_mesh_index| {
            mesh.sub_meshes[sub_mesh_index].index_offset = md.first_index + self.index_count;
            mesh.sub_meshes[sub_mesh_index].vertex_offset = md.first_vertex + self.vertex_count;
            mesh.sub_meshes[sub_mesh_index].index_count = @intCast(md.indices.items.len);
            mesh.sub_meshes[sub_mesh_index].vertex_count = @intCast(md.vertices.items.len);

            // Update index buffer
            {
                const data = Slice{
                    .data = @ptrCast(md.indices.items),
                    .size = md.indices.items.len * @sizeOf(u32),
                };

                std.debug.assert(self.index_buffer_size > data.size + self.index_buffer_offset);
                self.updateBuffer(data, self.index_buffer_offset, u32, self.index_buffer);

                self.index_buffer_offset += data.size;
            }

            // Update vertex buffer
            {
                const data = Slice{
                    .data = @ptrCast(md.vertices.items),
                    .size = md.vertices.items.len * @sizeOf(geometry.Vertex),
                };

                std.debug.assert(self.vertex_buffer_size > data.size + self.vertex_buffer_offset);
                self.updateBuffer(data, self.vertex_buffer_offset, u32, self.vertex_buffer);

                self.vertex_buffer_offset += data.size;
            }
        }

        for (mesh_data.items) |md| {
            self.index_count += @intCast(md.indices.items.len);
            self.vertex_count += @intCast(md.vertices.items.len);
        }

        const handle: MeshHandle = try self.mesh_pool.add(.{ .mesh = mesh });
        return handle;
    }

    pub fn getMesh(self: *Renderer, handle: MeshHandle) geometry.Mesh {
        const mesh = self.mesh_pool.getColumn(handle, .mesh) catch unreachable;
        return mesh;
    }

    pub fn loadLegacyMesh(self: *Renderer, path: [:0]const u8, vertex_layout_id: IdLocal) !LegacyMeshHandle {
        const vertex_layout = self.vertex_layouts_map.get(vertex_layout_id).?;

        var mesh: LegacyMesh = undefined;
        mesh.geometry = null;
        mesh.data = null;
        mesh.vertex_layout_id = vertex_layout_id;

        mesh.buffer_layout_desc.mSemanticBindings = std.mem.zeroes([19]u32);

        for (0..vertex_layout.mAttribCount) |i| {
            mesh.buffer_layout_desc.mSemanticBindings[@intCast(vertex_layout.mAttribs[i].mSemantic.bits)] = @intCast(i);
            mesh.buffer_layout_desc.mVerticesStrides[i] = @intCast(graphics.byteSizeOfBlock(vertex_layout.mAttribs[i].mFormat));
        }

        var load_desc = std.mem.zeroes(resource_loader.GeometryLoadDesc);
        load_desc.pFileName = path;
        load_desc.pVertexLayout = &vertex_layout;
        load_desc.ppGeometry = &mesh.geometry;
        load_desc.ppGeometryData = &mesh.data;
        load_desc.mFlags = resource_loader.GeometryLoadFlags.GEOMETRY_LOAD_FLAG_SHADOWED;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource__Overload3(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        mesh.loaded = true;

        const handle: LegacyMeshHandle = try self.legacy_mesh_pool.add(.{ .mesh = mesh });
        return handle;
    }

    pub fn getLegacyMesh(self: *Renderer, handle: LegacyMeshHandle) LegacyMesh {
        const mesh = self.legacy_mesh_pool.getColumn(handle, .mesh) catch unreachable;
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
            return renderer_types.InvalidResourceIndex;
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

    pub fn createStructuredBuffer(self: *Renderer, initial_data: Slice, debug_name: [:0]const u8) BufferHandle {
        var buffer: [*c]graphics.Buffer = null;

        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.pName = debug_name;
        load_desc.mDesc.bBindless = false;
        load_desc.mDesc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits };
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

    pub fn updateBuffer(self: *Renderer, data: Slice, dest_offset: u64, comptime T: type, handle: BufferHandle) void {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        _ = T;

        var update_desc = std.mem.zeroes(resource_loader.BufferUpdateDesc);
        update_desc.pBuffer = @ptrCast(buffer);
        update_desc.mDstOffset = dest_offset;
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
        return self.pso_manager.getPipeline(id);
    }

    pub fn getRootSignature(self: *Renderer, id: IdLocal) [*c]graphics.RootSignature {
        return self.pso_manager.getRootSignature(id);
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
        // graphics.getSupportedSwapchainFormat(self.renderer, &desc, graphics.ColorSpace.COLOR_SPACE_SDR_SRGB);
        desc.mColorFormat = graphics.TinyImageFormat.R10G10B10A2_UNORM;
        desc.mColorSpace = graphics.ColorSpace.COLOR_SPACE_SDR_SRGB;
        desc.mEnableVsync = self.vsync_enabled;
        desc.mFlags = graphics.SwapChainCreationFlags.SWAP_CHAIN_CREATION_FLAG_ENABLE_FOVEATED_RENDERING_VR;
        graphics.addSwapChain(self.renderer, &desc, &self.swap_chain);

        if (self.swap_chain == null) return false;

        return true;
    }

    fn createRenderTargets(self: *Renderer) void {
        const buffer_width: u32 = @intCast(self.window_width);
        const buffer_height: u32 = @intCast(self.window_height);

        // Depth buffers
        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Depth Buffer";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field3.depth = 0.0;
            rt_desc.mClearValue.__struct_field3.stencil = 0;
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.D32_SFLOAT;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = buffer_width;
            rt_desc.mHeight = buffer_height;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.depth_buffer);
            rt_desc.pName = "Depth Buffer Copy";
            rt_desc.mFormat = graphics.TinyImageFormat.R32_SFLOAT;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.depth_buffer_copy);

            var texture_desc = std.mem.zeroes(graphics.TextureDesc);
            texture_desc.mWidth = buffer_width;
            texture_desc.mHeight = buffer_height;
            texture_desc.mDepth = 1;
            texture_desc.mArraySize = 1;
            texture_desc.mMipLevels = 1;
            texture_desc.mFormat = graphics.TinyImageFormat.R16_UNORM;
            texture_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            texture_desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
            texture_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            texture_desc.bBindless = false;

            texture_desc.pName = "Linear Depth 0";
            self.linear_depth_buffers[0] = self.createTexture(texture_desc);

            texture_desc.pName = "Linear Depth 1";
            self.linear_depth_buffers[1] = self.createTexture(texture_desc);
        }

        // Shadow Buffers
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

        // GBuffer
        {
            {
                var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
                rt_desc.pName = "Base Color Buffer";
                rt_desc.mArraySize = 1;
                rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
                rt_desc.mDepth = 1;
                rt_desc.mFormat = graphics.TinyImageFormat.R8G8B8A8_SRGB;
                rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
                rt_desc.mWidth = buffer_width;
                rt_desc.mHeight = buffer_height;
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
                rt_desc.mFormat = graphics.TinyImageFormat.R8G8B8A8_SNORM;
                rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
                rt_desc.mWidth = buffer_width;
                rt_desc.mHeight = buffer_height;
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
                rt_desc.mWidth = buffer_width;
                rt_desc.mHeight = buffer_height;
                rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                rt_desc.mSampleQuality = 0;
                rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
                graphics.addRenderTarget(self.renderer, &rt_desc, &self.gbuffer_2);
            }
        }

        // Lighting
        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "Scene Color";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = hdr_format;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = buffer_width;
            rt_desc.mHeight = buffer_height;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            rt_desc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.scene_color);
            rt_desc.pName = "Scene Color Copy";
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.scene_color_copy);
        }

        // UI
        {
            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = "UI Overlay";
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field1 = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
            rt_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = buffer_width;
            rt_desc.mHeight = buffer_height;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            rt_desc.mDescriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.ui_overlay);
        }

        createBloomUAVs(self);
    }

    fn destroyRenderTargets(self: *Renderer) void {
        graphics.removeRenderTarget(self.renderer, self.depth_buffer);
        graphics.removeRenderTarget(self.renderer, self.depth_buffer_copy);
        var texture = self.getTexture(self.linear_depth_buffers[0]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.linear_depth_buffers[0]);
        texture = self.getTexture(self.linear_depth_buffers[1]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.linear_depth_buffers[1]);

        graphics.removeRenderTarget(self.renderer, self.shadow_depth_buffer);

        graphics.removeRenderTarget(self.renderer, self.gbuffer_0);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_1);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_2);

        graphics.removeRenderTarget(self.renderer, self.scene_color);
        graphics.removeRenderTarget(self.renderer, self.scene_color_copy);

        graphics.removeRenderTarget(self.renderer, self.ui_overlay);

        self.destroyBloomUAVs();
    }

    fn createBloomUAVs(self: *Renderer) void {
        // Common settings
        var texture_desc = std.mem.zeroes(graphics.TextureDesc);
        texture_desc.mDepth = 1;
        texture_desc.mArraySize = 1;
        texture_desc.mMipLevels = 1;
        texture_desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
        texture_desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
        texture_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
        texture_desc.bBindless = false;

        texture_desc.mFormat = graphics.TinyImageFormat.R8_UNORM;
        texture_desc.mWidth = @intCast(self.window_width);
        texture_desc.mHeight = @intCast(self.window_height);
        texture_desc.pName = "Luminance";
        self.luminance = self.createTexture(texture_desc);

        self.bloom_width = if (self.window_width > 2560) 1280 else 640;
        self.bloom_height = if (self.window_height > 1440) 768 else 384;

        texture_desc.mFormat = graphics.TinyImageFormat.R8_UINT;
        texture_desc.mWidth = self.bloom_width;
        texture_desc.mHeight = self.bloom_height;
        texture_desc.pName = "Luma Buffer";
        self.luma_lr = self.createTexture(texture_desc);

        texture_desc.mFormat = hdr_format;
        texture_desc.mWidth = self.bloom_width;
        texture_desc.mHeight = self.bloom_height;
        texture_desc.pName = "Bloom Buffer 1a";
        self.bloom_uav1[0] = self.createTexture(texture_desc);
        texture_desc.pName = "Bloom Buffer 1b";
        self.bloom_uav1[1] = self.createTexture(texture_desc);

        texture_desc.mWidth = self.bloom_width / 2;
        texture_desc.mHeight = self.bloom_height / 2;
        texture_desc.pName = "Bloom Buffer 2a";
        self.bloom_uav2[0] = self.createTexture(texture_desc);
        texture_desc.pName = "Bloom Buffer 2b";
        self.bloom_uav2[1] = self.createTexture(texture_desc);

        texture_desc.mWidth = self.bloom_width / 4;
        texture_desc.mHeight = self.bloom_height / 4;
        texture_desc.pName = "Bloom Buffer 3a";
        self.bloom_uav3[0] = self.createTexture(texture_desc);
        texture_desc.pName = "Bloom Buffer 3b";
        self.bloom_uav3[1] = self.createTexture(texture_desc);

        texture_desc.mWidth = self.bloom_width / 8;
        texture_desc.mHeight = self.bloom_height / 8;
        texture_desc.pName = "Bloom Buffer 4a";
        self.bloom_uav4[0] = self.createTexture(texture_desc);
        texture_desc.pName = "Bloom Buffer 4b";
        self.bloom_uav4[1] = self.createTexture(texture_desc);

        texture_desc.mWidth = self.bloom_width / 16;
        texture_desc.mHeight = self.bloom_height / 16;
        texture_desc.pName = "Bloom Buffer 5a";
        self.bloom_uav5[0] = self.createTexture(texture_desc);
        texture_desc.pName = "Bloom Buffer 5b";
        self.bloom_uav5[1] = self.createTexture(texture_desc);
    }

    fn destroyBloomUAVs(self: *Renderer) void {
        var texture = self.getTexture(self.luma_lr);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.luma_lr);

        texture = self.getTexture(self.luminance);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.luminance);

        texture = self.getTexture(self.bloom_uav1[0]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav1[0]);
        texture = self.getTexture(self.bloom_uav1[1]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav1[1]);

        texture = self.getTexture(self.bloom_uav2[0]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav2[0]);
        texture = self.getTexture(self.bloom_uav2[1]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav2[1]);

        texture = self.getTexture(self.bloom_uav3[0]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav3[0]);
        texture = self.getTexture(self.bloom_uav3[1]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav3[1]);

        texture = self.getTexture(self.bloom_uav4[0]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav4[0]);
        texture = self.getTexture(self.bloom_uav4[1]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav4[1]);

        texture = self.getTexture(self.bloom_uav5[0]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav5[0]);
        texture = self.getTexture(self.bloom_uav5[1]);
        resource_loader.removeResource__Overload2(texture);
        self.texture_pool.removeAssumeLive(self.bloom_uav5[1]);
    }

    fn createIBLTextures(self: *Renderer) void {
        // Create empty texture for BRDF integration map
        {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = brdf_lut_texture_size;
            desc.mHeight = brdf_lut_texture_size;
            desc.mDepth = 1;
            desc.mArraySize = 1;
            desc.mMipLevels = 1;
            desc.mFormat = graphics.TinyImageFormat.R32G32_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "BRDF LUT";
            self.brdf_lut_texture = self.createTexture(desc);
        }

        // Create empty texture for Irradiance map
        {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = irradiance_texture_size;
            desc.mHeight = irradiance_texture_size;
            desc.mDepth = 1;
            desc.mArraySize = 6;
            desc.mMipLevels = 1;
            desc.mFormat = graphics.TinyImageFormat.R32G32B32A32_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE_CUBE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "Irradiance Map";
            self.irradiance_texture = self.createTexture(desc);
        }

        // Create empty texture for Specular map
        {
            var desc = std.mem.zeroes(graphics.TextureDesc);
            desc.mWidth = specular_texture_size;
            desc.mHeight = specular_texture_size;
            desc.mDepth = 1;
            desc.mArraySize = 6;
            desc.mMipLevels = specular_texture_mips;
            desc.mFormat = graphics.TinyImageFormat.R32G32B32A32_SFLOAT;
            desc.mStartState = graphics.ResourceState.RESOURCE_STATE_SHADER_RESOURCE;
            desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE_CUBE.bits };
            desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            desc.bBindless = false;
            desc.pName = "Specular Map";
            self.specular_texture = self.createTexture(desc);
        }
    }

    fn createResolutionIndependentRenderTargets(self: *Renderer) void {
        _ = self;
    }

    fn destroyResolutionIndependentRenderTargets(self: *Renderer) void {
        _ = self;
    }

    fn createCompositeSDRDescriptorSet(self: *Renderer) void {
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.pRootSignature = self.getRootSignature(IdLocal.init("composite_sdr"));
        desc.mMaxSets = data_buffer_count;

        graphics.addDescriptorSet(self.renderer, &desc, @ptrCast(&self.composite_sdr_pass_descriptor_set));
    }

    fn prepareCompositeSDRDescriptorSet(self: *Renderer) void {
        for (0..data_buffer_count) |frame_index| {
            var params: [2]graphics.DescriptorData = undefined;

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "MainBuffer";
            params[0].__union_field3.ppTextures = @ptrCast(&self.scene_color.*.pTexture);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "OverlayBuffer";
            params[1].__union_field3.ppTextures = @ptrCast(&self.ui_overlay.*.pTexture);

            graphics.updateDescriptorSet(self.renderer, @intCast(frame_index), self.composite_sdr_pass_descriptor_set, params.len, @ptrCast(&params));
        }
    }

    fn createBuffersVisualizationDescriptorSet(self: *Renderer) void {
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.pRootSignature = self.getRootSignature(IdLocal.init("buffer_visualizer"));
        desc.mMaxSets = data_buffer_count;

        graphics.addDescriptorSet(self.renderer, &desc, @ptrCast(&self.buffers_visualization_descriptor_set));
    }

    fn prepareBuffersVisualizationDescriptorSet(self: *Renderer) void {
        for (0..data_buffer_count) |frame_index| {
            var params: [4]graphics.DescriptorData = undefined;

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "GBuffer0";
            params[0].__union_field3.ppTextures = @ptrCast(&self.gbuffer_0.*.pTexture);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "GBuffer1";
            params[1].__union_field3.ppTextures = @ptrCast(&self.gbuffer_1.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "GBuffer2";
            params[2].__union_field3.ppTextures = @ptrCast(&self.gbuffer_2.*.pTexture);
            params[3] = std.mem.zeroes(graphics.DescriptorData);
            params[3].pName = "OverlayBuffer";
            params[3].__union_field3.ppTextures = @ptrCast(&self.ui_overlay.*.pTexture);

            graphics.updateDescriptorSet(self.renderer, @intCast(frame_index), self.buffers_visualization_descriptor_set, params.len, @ptrCast(&params));
        }
    }
};


pub const LegacyMesh = struct {
    geometry: [*c]resource_loader.Geometry,
    data: [*c]resource_loader.GeometryData,
    buffer_layout_desc: resource_loader.GeometryBufferLayoutDesc,
    vertex_layout_id: IdLocal,
    loaded: bool,
};

pub const Material = struct {
    albedo_color: [4]f32,
    uv_tiling_offset: [4]f32,
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

const MaterialPool = Pool(16, 16, Material, struct { material: Material, buffer_offset: u32, pipeline_ids: PassPipelineIds, alpha_test: bool });
pub const MaterialHandle = MaterialPool.Handle;

const MeshPool = Pool(16, 16, geometry.Mesh, struct { mesh: geometry.Mesh });
pub const MeshHandle = MeshPool.Handle;

const LegacyMeshPool = Pool(16, 16, LegacyMesh, struct { mesh: LegacyMesh });
pub const LegacyMeshHandle = LegacyMeshPool.Handle;

const TexturePool = Pool(16, 16, graphics.Texture, struct { texture: [*c]graphics.Texture });
pub const TextureHandle = TexturePool.Handle;

const BufferPool = Pool(16, 16, graphics.Buffer, struct { buffer: [*c]graphics.Buffer });
pub const BufferHandle = BufferPool.Handle;

pub const Slice = extern struct {
    data: ?*const anyopaque,
    size: u64,
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
