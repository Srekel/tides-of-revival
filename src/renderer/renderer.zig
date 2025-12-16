const std = @import("std");

const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const file_system = zforge.file_system;
const font = zforge.font;
const geometry = @import("geometry.zig");
const graphics = zforge.graphics;
const IdLocal = @import("../core/core.zig").IdLocal;
const memory = zforge.memory;
const OpaqueSlice = util.OpaqueSlice;
const Pool = @import("zpool").Pool;
const profiler = @import("profiler.zig");
const pso = @import("pso.zig");
const renderer_types = @import("types.zig");
const resource_loader = zforge.resource_loader;
const util = @import("../util.zig");
const window = @import("window.zig");
const world_patch_manager = @import("../worldpatch/world_patch_manager.zig");
const zforge = @import("zforge");
const zglfw = @import("zglfw");
const zgui = @import("zgui");
const zm = @import("zmath");
const ztracy = @import("ztracy");

const TerrainPass = @import("passes/terrain_pass.zig").TerrainPass;
const DynamicGeometryPass = @import("passes/dynamic_geometry_pass.zig").DynamicGeometryPass;
const StaticGeometryPass = @import("passes/static_geometry_pass.zig").StaticGeometryPass;
const DeferredShadingPass = @import("passes/deferred_shading_pass.zig").DeferredShadingPass;
const ProceduralSkyboxPass = @import("passes/procedural_skybox_pass.zig").ProceduralSkyboxPass;
const WaterPass = @import("passes/water_pass.zig").WaterPass;
const PostProcessingPass = @import("passes/post_processing_pass.zig").PostProcessingPass;
const UIPass = @import("passes/ui_pass.zig").UIPass;
const Im3dPass = @import("passes/im3d_pass.zig").Im3dPass;

pub const ReloadDesc = graphics.ReloadDesc;
pub const cascaded_shadow_resolution: u32 = 2048;

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
    pub const cascades_max_count: u32 = 4;
    pub const debug_line_point_count_max = 200000;

    allocator: std.mem.Allocator = undefined,
    ecsu_world: ecsu.World = undefined,
    world_patch_mgr: *world_patch_manager.WorldPatchManager = undefined,
    renderer: [*c]graphics.Renderer = null,
    window: *window.Window = undefined,
    window_width: i32 = 0,
    window_height: i32 = 0,
    time: f64 = 0.0,
    vsync_enabled: bool = false,
    draw_debug_lines: bool = false,

    swap_chain: [*c]graphics.SwapChain = null,
    gpu_cmd_ring: graphics.GpuCmdRing = undefined,
    image_acquired_semaphore: [*c]graphics.Semaphore = null,
    swap_chain_image_index: u32 = 0,
    graphics_queue: [*c]graphics.Queue = null,
    frame_index: u32 = 0,
    profiler: profiler.Profiler = undefined,
    gpu_frame_profile_index: usize = 0,
    gpu_terrain_pass_profile_index: usize = 0,
    gpu_geometry_pass_profile_index: usize = 0,
    gpu_gpu_driven_pass_profile_index: usize = 0,

    // Debug Line Buffers
    debug_frame_uniform_buffers: [data_buffer_count]BufferHandle = undefined,
    debug_line_vertex_buffers: [data_buffer_count]BufferHandle = undefined,
    debug_line_args_buffers: [data_buffer_count]BufferHandle = undefined,
    debug_line_renderer_clear_uav_descriptor_set: [*c]graphics.DescriptorSet = undefined,
    debug_line_renderer_draw_descriptor_set: [*c]graphics.DescriptorSet = undefined,

    // TODO: Create a scene structs
    // Scene Data
    // ==========
    time_of_day_01: f32 = 0.0,
    sun_light: renderer_types.DirectionalLight = undefined,
    moon_light: renderer_types.DirectionalLight = undefined,
    height_fog_settings: renderer_types.HeightFogSettings = undefined,
    ocean_tiles: std.ArrayList(renderer_types.OceanTile) = undefined,
    dynamic_entities: std.ArrayList(renderer_types.DynamicEntity) = undefined,
    added_static_entities: std.ArrayList(renderer_types.RenderableEntity) = undefined,
    removed_static_entities: std.ArrayList(renderer_types.RenderableEntityId) = undefined,
    ui_images: std.ArrayList(renderer_types.UiImage) = undefined,

    // GPU Bindless Buffers
    // ====================
    // These buffers are accessible to all shaders
    light_buffer: ElementBindlessBuffer = undefined,
    light_matrix_buffer: ElementBindlessBuffer = undefined,
    mesh_buffer: ElementBindlessBuffer = undefined,
    material_buffer: ElementBindlessBuffer = undefined,
    renderable_buffer: ElementBindlessBuffer = undefined,

    // Resources
    // =========
    renderable_map: RenderableHashMap = undefined,
    renderable_item_map: RenderableToRenderableItems = undefined,
    // TODO: Figure out if we need to store this data on the CPU
    meshes: std.ArrayList(Mesh) = undefined,
    mesh_map: MeshHashMap = undefined,
    // materials: std.ArrayList(GpuMaterial) = undefined,
    material_map: MaterialMap = undefined,

    // Bindless Sampler
    linear_repeat_sampler: [*c]graphics.Sampler = null,

    // Render Passes
    // =============
    terrain_pass: TerrainPass = undefined,
    dynamic_geometry_pass: DynamicGeometryPass = undefined,
    static_geometry_pass: StaticGeometryPass = undefined,
    deferred_shading_pass: DeferredShadingPass = undefined,
    procedural_skybox_pass: ProceduralSkyboxPass = undefined,
    water_pass: WaterPass = undefined,
    post_processing_pass: PostProcessingPass = undefined,
    ui_pass: UIPass = undefined,
    im3d_pass: Im3dPass = undefined,

    // Render Targets
    // ==============
    // Depth
    depth_buffer: [*c]graphics.RenderTarget = null,
    depth_buffer_copy: [*c]graphics.RenderTarget = null,
    linear_depth_buffers: [2]TextureHandle = .{ undefined, undefined },

    // Shadows
    shadow_pssm_factor: f32 = 0.85,
    shadow_cascade_max_distance: f32 = 250,
    shadow_cascade_depths: [cascades_max_count]f32 = undefined,
    shadow_views: [cascades_max_count]RenderView = undefined,
    shadow_depth_buffers: [cascades_max_count][*c]graphics.RenderTarget = undefined,

    // GBuffer
    gbuffer_0: [*c]graphics.RenderTarget = null,
    gbuffer_1: [*c]graphics.RenderTarget = null,
    gbuffer_2: [*c]graphics.RenderTarget = null,

    // Lighting
    scene_color: [*c]graphics.RenderTarget = null,
    scene_color_copy: [*c]graphics.RenderTarget = null,

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

    legacy_mesh_pool: LegacyMeshPool = undefined,
    texture_pool: TexturePool = undefined,
    buffer_pool: BufferPool = undefined,
    pso_manager: pso.PSOManager = undefined,

    render_imgui: bool = false,

    // Buffers Visualization
    // =====================
    selected_visualization_mode: i32 = -1,
    buffers_visualization_descriptor_set: [*c]graphics.DescriptorSet = undefined,

    // Composite SDR Pass
    // ==================
    tonemapper_pass_descriptor_set: [*c]graphics.DescriptorSet = undefined,

    pub const Error = error{
        NotInitialized,
        SwapChainNotInitialized,
        FontSystemNotInitialized,
        MemorySystemNotInitialized,
        FileSystemNotInitialized,
    };

    pub fn init(self: *Renderer, wnd: *window.Window, ecsu_world: ecsu.World, world_patch_mgr: *world_patch_manager.WorldPatchManager, allocator: std.mem.Allocator) Error!void {
        self.allocator = allocator;
        self.ecsu_world = ecsu_world;
        self.world_patch_mgr = world_patch_mgr;
        self.window = wnd;
        self.window_width = wnd.frame_buffer_size[0];
        self.window_height = wnd.frame_buffer_size[1];
        self.time = 0.0;
        self.vsync_enabled = false;

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

        zforge.log.initLog("Tides Renderer", zforge.log.LogLevel.eALL);

        var renderer_desc = std.mem.zeroes(graphics.RendererDesc);
        renderer_desc.mShaderTarget = .SHADER_TARGET_6_8;
        renderer_desc.mEnableGpuBasedValidation = false;
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

        self.profiler.init(self, self.allocator);

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

        var debug_line_vertex_layout = std.mem.zeroes(graphics.VertexLayout);
        debug_line_vertex_layout.mBindingCount = 1;
        debug_line_vertex_layout.mAttribCount = 2;
        debug_line_vertex_layout.mAttribs[0].mSemantic = graphics.ShaderSemantic.SEMANTIC_POSITION;
        debug_line_vertex_layout.mAttribs[0].mFormat = graphics.TinyImageFormat.R32G32B32_SFLOAT;
        debug_line_vertex_layout.mAttribs[0].mBinding = 0;
        debug_line_vertex_layout.mAttribs[0].mLocation = 0;
        debug_line_vertex_layout.mAttribs[0].mOffset = 0;
        debug_line_vertex_layout.mAttribs[1].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
        debug_line_vertex_layout.mAttribs[1].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
        debug_line_vertex_layout.mAttribs[1].mBinding = 0;
        debug_line_vertex_layout.mAttribs[1].mLocation = 1;
        debug_line_vertex_layout.mAttribs[1].mOffset = @sizeOf(f32) * 3;
        self.vertex_layouts_map.put(IdLocal.init("debug_line"), debug_line_vertex_layout) catch unreachable;

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

            vertex_layout.mBindingCount = 5;
            vertex_layout.mAttribCount = 5;
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
            vertex_layout.mAttribs[4].mSemantic = graphics.ShaderSemantic.SEMANTIC_COLOR;
            vertex_layout.mAttribs[4].mFormat = graphics.TinyImageFormat.R8G8B8A8_UNORM;
            vertex_layout.mAttribs[4].mBinding = 4;
            vertex_layout.mAttribs[4].mLocation = 4;
            vertex_layout.mAttribs[4].mOffset = 0;
            self.vertex_layouts_map.put(IdLocal.init("pos_uv0_nor_tan_col"), vertex_layout) catch unreachable;
        }

        // Bindless Samplers
        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;

            graphics.addSampler(self.renderer, &desc, true, &self.linear_repeat_sampler);
        }

        self.frame_index = 0;

        self.legacy_mesh_pool = LegacyMeshPool.initMaxCapacity(allocator) catch unreachable;
        self.texture_pool = TexturePool.initMaxCapacity(allocator) catch unreachable;
        self.buffer_pool = BufferPool.initMaxCapacity(allocator) catch unreachable;
        self.pso_manager = pso.PSOManager{};
        self.pso_manager.init(self, allocator) catch unreachable;

        zgui.init(allocator);
        _ = zgui.io.addFontFromFile("content/fonts/Roboto-Medium.ttf", 16.0);

        self.renderable_map = RenderableHashMap.init(allocator);
        self.renderable_item_map = RenderableToRenderableItems.init(allocator);

        self.light_buffer.init(self, 2048, @sizeOf(renderer_types.GpuLight), false, "GpuLight Buffer");
        self.light_matrix_buffer.init(self, 4, @sizeOf([16]f32), false, "Light Matrix Buffer");

        self.meshes = std.ArrayList(Mesh).init(allocator);
        self.mesh_map = MeshHashMap.init(allocator);
        self.mesh_buffer.init(self, 1024, @sizeOf(GPUMesh), false, "GpuMesh Buffer");
        self.renderable_buffer.init(self, 1024 * lods_per_renderable_max_count * materials_per_renderable_max_count, @sizeOf(GpuRenderableItem), false, "Gpu Renderable Items");

        self.material_buffer.init(self, 64, @sizeOf(GpuMaterial), false, "Material Buffer");
        self.material_map = MaterialMap.init(allocator);

        // Debug Line Rendering Resources
        {
            self.debug_frame_uniform_buffers = blk: {
                var buffers: [data_buffer_count]BufferHandle = undefined;
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = self.createUniformBuffer(renderer_types.DebugFrame);
                }

                break :blk buffers;
            };

            self.debug_line_vertex_buffers = blk: {
                const buffer_creation_desc = BufferCreationDesc{
                    .bindless = true,
                    .descriptors = .{ .bits = (graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_VERTEX_BUFFER.bits) },
                    .start_state = .RESOURCE_STATE_SHADER_RESOURCE,
                    .size = debug_line_point_count_max * 16,
                    .debug_name = "Debug Lines",
                };
                var buffers: [data_buffer_count]BufferHandle = undefined;
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = self.createBuffer(buffer_creation_desc);
                }

                break :blk buffers;
            };

            self.debug_line_args_buffers = blk: {
                const buffer_creation_desc = BufferCreationDesc{
                    .bindless = true,
                    .descriptors = .{ .bits = (graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits) },
                    .start_state = .RESOURCE_STATE_SHADER_RESOURCE,
                    .size = 16 * @sizeOf(u32),
                    .debug_name = "Debug Line Args",
                };

                var buffers: [data_buffer_count]BufferHandle = undefined;
                for (buffers, 0..) |_, buffer_index| {
                    buffers[buffer_index] = self.createBuffer(buffer_creation_desc);
                }

                break :blk buffers;
            };
        }

        self.terrain_pass.init(self, self.ecsu_world, self.world_patch_mgr, self.allocator);
        self.dynamic_geometry_pass.init(self, self.allocator);
        self.static_geometry_pass.init(self, self.allocator);
        self.deferred_shading_pass.init(self, self.allocator);
        self.procedural_skybox_pass.init(self, self.allocator);
        self.water_pass.init(self, self.allocator);
        self.post_processing_pass.init(self, self.allocator);
        self.ui_pass.init(self, self.allocator);
        self.im3d_pass.init(self, self.allocator);

        // Scene Data
        self.ocean_tiles = std.ArrayList(renderer_types.OceanTile).init(self.allocator);
        self.dynamic_entities = std.ArrayList(renderer_types.DynamicEntity).init(self.allocator);
        self.added_static_entities = std.ArrayList(renderer_types.RenderableEntity).init(self.allocator);
        self.removed_static_entities = std.ArrayList(renderer_types.RenderableEntityId).init(self.allocator);
        self.ui_images = std.ArrayList(renderer_types.UiImage).init(self.allocator);
    }

    pub fn exit(self: *Renderer) void {
        // Scene Data
        self.ocean_tiles.deinit();
        self.added_static_entities.deinit();
        self.removed_static_entities.deinit();
        self.dynamic_entities.deinit();
        self.ui_images.deinit();

        self.im3d_pass.destroy();
        self.ui_pass.destroy();
        self.post_processing_pass.destroy();
        self.water_pass.destroy();
        self.procedural_skybox_pass.destroy();
        self.deferred_shading_pass.destroy();
        self.static_geometry_pass.destroy();
        self.dynamic_geometry_pass.destroy();
        self.terrain_pass.destroy();

        self.pso_manager.exit();

        graphics.removeDescriptorSet(self.renderer, self.debug_line_renderer_draw_descriptor_set);
        graphics.removeDescriptorSet(self.renderer, self.debug_line_renderer_clear_uav_descriptor_set);
        graphics.removeDescriptorSet(self.renderer, self.tonemapper_pass_descriptor_set);
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

        self.renderable_item_map.deinit();
        self.renderable_map.deinit();
        self.mesh_map.deinit();
        self.meshes.deinit();
        self.material_map.deinit();

        var legacy_mesh_handles = self.legacy_mesh_pool.liveHandles();
        while (legacy_mesh_handles.next()) |handle| {
            const mesh = self.legacy_mesh_pool.getColumn(handle, .mesh) catch unreachable;
            resource_loader.removeResource__Overload3(mesh.geometry);
            resource_loader.removeResource__Overload4(mesh.data);
        }
        self.legacy_mesh_pool.deinit();

        self.vertex_layouts_map.deinit();

        graphics.removeSampler(self.renderer, self.linear_repeat_sampler);

        graphics.exitQueue(self.renderer, self.graphics_queue);
        self.gpu_cmd_ring.destroy(self.renderer);
        graphics.exitSemaphore(self.renderer, self.image_acquired_semaphore);

        self.profiler.shutdown();

        self.destroyResolutionIndependentRenderTargets();

        font.exitFontSystem();
        resource_loader.exitResourceLoaderInterface(self.renderer);
        graphics.exitRenderer(self.renderer);

        font.platformExitFontSystem();
        zforge.log.exitLog();
        file_system.exitFileSystem();
    }

    pub fn startGpuProfile(self: *Renderer, cmd_list: [*c]graphics.Cmd, name: []const u8) usize {
        return self.profiler.startProfile(cmd_list, name);
    }

    pub fn endGpuProfile(self: *Renderer, cmd_list: [*c]graphics.Cmd, profile_index: usize) void {
        self.profiler.endProfile(cmd_list, profile_index);
    }

    pub fn getFrameAvgTimeMs(self: *Renderer) f32 {
        return getProfilerAvgTimeMs(self.frame_profiler_index);
    }

    pub fn getProfilerAvgTimeMs(self: *Renderer, profiler_index: usize) f32 {
        const profile_data = self.profiler.profiles.items[profiler_index];
        var sum: f64 = 0;

        for (0..profiler.ProfileData.filter_size) |i| {
            sum += profile_data.time_samples[i];
        }
        sum /= 64.0;
        return @floatCast(sum);
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

            // Debug Line Rendering Descriptor Sets
            {
                var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
                desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
                desc.pRootSignature = self.getRootSignature(IdLocal.init("debug_line_rendering_clear"));
                desc.mMaxSets = data_buffer_count;

                graphics.addDescriptorSet(self.renderer, &desc, @ptrCast(&self.debug_line_renderer_clear_uav_descriptor_set));

                desc.pRootSignature = self.getRootSignature(IdLocal.init("debug_line_rendering_draw"));
                graphics.addDescriptorSet(self.renderer, &desc, @ptrCast(&self.debug_line_renderer_draw_descriptor_set));
            }

            self.createCompositeSDRDescriptorSet();
            self.createBuffersVisualizationDescriptorSet();

            self.terrain_pass.createDescriptorSets();
            self.dynamic_geometry_pass.createDescriptorSets();
            self.static_geometry_pass.createDescriptorSets();
            self.deferred_shading_pass.createDescriptorSets();
            self.procedural_skybox_pass.createDescriptorSets();
            self.water_pass.createDescriptorSets();
            self.post_processing_pass.createDescriptorSets();
            self.ui_pass.createDescriptorSets();
            self.im3d_pass.createDescriptorSets();
        }

        self.prepareCompositeSDRDescriptorSet();
        self.prepareBuffersVisualizationDescriptorSet();

        self.terrain_pass.prepareDescriptorSets();
        self.dynamic_geometry_pass.prepareDescriptorSets();
        self.static_geometry_pass.prepareDescriptorSets();
        self.deferred_shading_pass.prepareDescriptorSets();
        self.procedural_skybox_pass.prepareDescriptorSets();
        self.water_pass.prepareDescriptorSets();
        self.post_processing_pass.prepareDescriptorSets();
        self.ui_pass.prepareDescriptorSets();
        self.im3d_pass.prepareDescriptorSets();

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
            self.terrain_pass.unloadDescriptorSets();
            self.dynamic_geometry_pass.unloadDescriptorSets();
            self.static_geometry_pass.unloadDescriptorSets();
            self.deferred_shading_pass.unloadDescriptorSets();
            self.procedural_skybox_pass.unloadDescriptorSets();
            self.water_pass.unloadDescriptorSets();
            self.post_processing_pass.unloadDescriptorSets();
            self.ui_pass.unloadDescriptorSets();
            self.im3d_pass.unloadDescriptorSets();
        }
    }

    pub fn requestReload(self: *Renderer, reload_desc: graphics.ReloadDesc) void {
        self.onUnload(reload_desc);
        self.onLoad(reload_desc) catch unreachable;
    }

    // NOTE: Disable VSync for now. Shadows flicker when it is enabled
    pub fn toggleVSync(self: *Renderer) void {
        _ = self;
        // self.vsync_enabled = !self.vsync_enabled;
    }

    pub fn reloadShaders(self: *Renderer) void {
        const reload_desc = graphics.ReloadDesc{
            .mType = .{ .SHADER = true },
        };
        self.requestReload(reload_desc);
    }

    pub fn getSH9BufferIndex(self: *Renderer) u32 {
        const handle = self.procedural_skybox_pass.sh9_skylight_buffers[self.frame_index];
        return self.getBufferBindlessIndex(handle);
    }

    pub fn update(self: *Renderer, update_desc: renderer_types.UpdateDesc) void {
        self.time_of_day_01 = update_desc.time_of_day_01;
        self.sun_light = update_desc.sun_light;
        self.moon_light = update_desc.moon_light;

        var lights = std.ArrayList(renderer_types.GpuLight).init(self.allocator);
        lights.append(.{
            .light_type = 0,
            .position = update_desc.sun_light.direction,
            .color = update_desc.sun_light.color,
            .intensity = update_desc.sun_light.intensity,
            .shadow_intensity = update_desc.sun_light.shadow_intensity,
        }) catch unreachable;

        lights.append(.{
            .light_type = 0,
            .position = update_desc.moon_light.direction,
            .color = update_desc.moon_light.color,
            .intensity = update_desc.moon_light.intensity,
            .shadow_intensity = update_desc.moon_light.shadow_intensity,
        }) catch unreachable;

        for (update_desc.point_lights.items) |point_light| {
            lights.append(.{
                .light_type = 1,
                .position = point_light.position,
                .radius = point_light.radius,
                .color = point_light.color,
                .intensity = point_light.intensity,
            }) catch unreachable;
        }

        const data_slice = OpaqueSlice{
            .data = @ptrCast(lights.items),
            .size = @sizeOf(renderer_types.GpuLight) * lights.items.len,
        };
        self.updateBuffer(data_slice, self.light_buffer.offset, renderer_types.GpuLight, self.light_buffer.buffer);
        self.light_buffer.element_count = @intCast(lights.items.len);
        self.height_fog_settings.color = update_desc.height_fog.color;
        self.height_fog_settings.density = update_desc.height_fog.density;

        self.ocean_tiles.clearRetainingCapacity();
        self.ocean_tiles.appendSlice(update_desc.ocean_tiles.items) catch unreachable;

        self.dynamic_entities.clearRetainingCapacity();
        self.dynamic_entities.appendSlice(update_desc.dynamic_entities.items) catch unreachable;

        self.added_static_entities.clearRetainingCapacity();
        self.removed_static_entities.clearRetainingCapacity();

        self.added_static_entities.appendSlice(update_desc.added_static_entities.items) catch unreachable;
        self.removed_static_entities.appendSlice(update_desc.removed_static_entities.items) catch unreachable;

        self.ui_images.clearRetainingCapacity();
        self.ui_images.appendSlice(update_desc.ui_images.items) catch unreachable;
    }

    pub fn draw(self: *Renderer) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Render", 0x00_ff_ff_00);
        defer trazy_zone.End();

        self.drawRenderSettings();
        self.generateShadowViews();

        const render_view = self.generateRenderView();

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

        self.updateStep(render_view, cmd_list);

        self.gpu_frame_profile_index = self.startGpuProfile(cmd_list, "GPU Frame");

        // Debug Line Rendering: Clear UAVs
        {
            // Update Uniform Buffer
            var debug_frame = std.mem.zeroes(renderer_types.DebugFrame);
            zm.storeMat(&debug_frame.view, zm.transpose(render_view.view));
            zm.storeMat(&debug_frame.proj, zm.transpose(render_view.projection));
            zm.storeMat(&debug_frame.view_proj, zm.transpose(render_view.view_projection));
            zm.storeMat(&debug_frame.view_proj_inv, zm.transpose(render_view.view_projection_inverse));
            debug_frame.debug_line_point_count_max = debug_line_point_count_max;
            debug_frame.debug_line_point_args_buffer_index = self.getBufferBindlessIndex(self.debug_line_args_buffers[self.frame_index]);
            debug_frame.debug_line_vertex_buffer_index = self.getBufferBindlessIndex(self.debug_line_vertex_buffers[self.frame_index]);
            debug_frame._padding1 = 42;

            const uniform_buffer_handle = self.debug_frame_uniform_buffers[self.frame_index];
            const frame_data = OpaqueSlice{
                .data = @ptrCast(&debug_frame),
                .size = @sizeOf(renderer_types.DebugFrame),
            };
            self.updateBuffer(frame_data, 0, renderer_types.DebugFrame, uniform_buffer_handle);

            // Resource Barriers
            const debug_line_args_buffer = self.getBuffer(self.debug_line_args_buffers[self.frame_index]);
            const line_vertex_buffer = self.getBuffer(self.debug_line_vertex_buffers[self.frame_index]);
            {
                const buffer_barriers = [_]graphics.BufferBarrier{
                    graphics.BufferBarrier.init(debug_line_args_buffer, .RESOURCE_STATE_COMMON, .RESOURCE_STATE_UNORDERED_ACCESS),
                    graphics.BufferBarrier.init(line_vertex_buffer, .RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER, .RESOURCE_STATE_UNORDERED_ACCESS),
                };
                graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
            }

            // Update Descriptor Set
            const descriptor_set = self.debug_line_renderer_clear_uav_descriptor_set;

            {
                var uniform_buffer = self.getBuffer(uniform_buffer_handle);

                var params: [1]graphics.DescriptorData = undefined;
                params[0] = std.mem.zeroes(graphics.DescriptorData);
                params[0].pName = "g_DebugFrame";
                params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                graphics.updateDescriptorSet(self.renderer, self.frame_index, descriptor_set, @intCast(params.len), @ptrCast(&params));
            }

            // Dispatch
            const pipeline_id = IdLocal.init("debug_line_rendering_clear");
            const pipeline = self.getPSO(pipeline_id);
            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, self.frame_index, descriptor_set);
            graphics.cmdDispatch(cmd_list, 1, 1, 1);
        }

        // Shadow Map Pass
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Shadow Map Pass", 0x00_ff_00_00);
            defer trazy_zone1.End();

            const shadow_profile_index = self.startGpuProfile(cmd_list, "Shadow Maps");
            defer self.endGpuProfile(cmd_list, shadow_profile_index);

            for (0..cascades_max_count) |cascade_index| {
                var profile_name_buffer: [256]u8 = undefined;
                const profile_name = std.fmt.bufPrintZ(
                    profile_name_buffer[0..profile_name_buffer.len],
                    "Shadow View {d}",
                    .{cascade_index},
                ) catch unreachable;

                const shadow_view_profile_index = self.startGpuProfile(cmd_list, profile_name);
                defer self.endGpuProfile(cmd_list, shadow_view_profile_index);

                var input_barriers = [_]graphics.RenderTargetBarrier{
                    graphics.RenderTargetBarrier.init(self.shadow_depth_buffers[cascade_index], .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_DEPTH_WRITE),
                };
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

                var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
                bind_render_targets_desc.mRenderTargetCount = 0;
                bind_render_targets_desc.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
                bind_render_targets_desc.mDepthStencil.pDepthStencil = self.shadow_depth_buffers[cascade_index];
                bind_render_targets_desc.mDepthStencil.mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;
                graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

                const shadow_map_resolution: f32 = @floatFromInt(cascaded_shadow_resolution);
                graphics.cmdSetViewport(cmd_list, 0.0, 0.0, shadow_map_resolution, shadow_map_resolution, 0.0, 1.0);
                graphics.cmdSetScissor(cmd_list, 0, 0, cascaded_shadow_resolution, cascaded_shadow_resolution);

                self.terrain_pass.renderShadowMap(cmd_list, self.shadow_views[cascade_index], @intCast(cascade_index));
                self.dynamic_geometry_pass.renderShadowMap(cmd_list, self.shadow_views[cascade_index], @intCast(cascade_index));
                self.static_geometry_pass.renderShadowMap(cmd_list, self.shadow_views[cascade_index], @intCast(cascade_index));

                input_barriers[0].mCurrentState = .RESOURCE_STATE_DEPTH_WRITE;
                input_barriers[0].mNewState = .RESOURCE_STATE_SHADER_RESOURCE;
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, input_barriers.len, @ptrCast(&input_barriers));

                graphics.cmdBindRenderTargets(cmd_list, null);
            }
        }

        // GBuffer Pass
        {
            const profile_index = self.startGpuProfile(cmd_list, "GBuffer");
            defer self.endGpuProfile(cmd_list, profile_index);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "GBuffer Pass", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.gbuffer_0, .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.gbuffer_1, .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.gbuffer_2, .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.depth_buffer, .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_DEPTH_WRITE),
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

            self.terrain_pass.renderGBuffer(cmd_list, render_view);
            self.dynamic_geometry_pass.renderGBuffer(cmd_list, render_view);
            self.static_geometry_pass.renderGBuffer(cmd_list, render_view);

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Compute: Generate Procedural Skybox
        {
            const profile_index = self.startGpuProfile(cmd_list, "Compute Procedural Skybox");
            defer self.endGpuProfile(cmd_list, profile_index);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Compute Procedural Skybox", 0x00_ff_00_00);
            defer trazy_zone1.End();

            self.procedural_skybox_pass.renderProceduralSkybox(cmd_list, render_view);

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Deferred Shading
        {
            const profile_index = self.startGpuProfile(cmd_list, "Deferred Shading");
            defer self.endGpuProfile(cmd_list, profile_index);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Deferred Shading", 0x00_ff_00_00);
            defer trazy_zone1.End();

            var input_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.scene_color, .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_RENDER_TARGET),
                graphics.RenderTargetBarrier.init(self.gbuffer_0, .RESOURCE_STATE_RENDER_TARGET, .RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.gbuffer_1, .RESOURCE_STATE_RENDER_TARGET, .RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.gbuffer_2, .RESOURCE_STATE_RENDER_TARGET, .RESOURCE_STATE_SHADER_RESOURCE),
                graphics.RenderTargetBarrier.init(self.depth_buffer, .RESOURCE_STATE_DEPTH_WRITE, .RESOURCE_STATE_SHADER_RESOURCE),
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

            self.deferred_shading_pass.render(cmd_list, render_view);

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Graphics: Draw Procedural Skybox
        {
            const profile_index = self.startGpuProfile(cmd_list, "Draw Procedural Skybox");
            defer self.endGpuProfile(cmd_list, profile_index);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Draw Procedural Skybox", 0x00_ff_00_00);
            defer trazy_zone1.End();

            self.procedural_skybox_pass.drawSkybox(cmd_list, render_view);

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Water Pass
        {
            const profile_index = self.startGpuProfile(cmd_list, "Water");
            defer self.endGpuProfile(cmd_list, profile_index);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Water", 0x00_ff_00_00);
            defer trazy_zone1.End();

            self.water_pass.render(cmd_list, render_view);

            graphics.cmdBindRenderTargets(cmd_list, null);
        }

        // Post Processing
        {
            const profile_index = self.startGpuProfile(cmd_list, "Post");
            defer self.endGpuProfile(cmd_list, profile_index);

            const trazy_zone1 = ztracy.ZoneNC(@src(), "Post Processing", 0x00_ff_00_00);
            defer trazy_zone1.End();

            self.post_processing_pass.render(cmd_list, render_view);
        }

        // Tonemapper
        {
            const trazy_zone1 = ztracy.ZoneNC(@src(), "Tonemapper", 0x00_ff_00_00);
            defer trazy_zone1.End();

            const profile_index = self.startGpuProfile(cmd_list, "Tonemapper");
            defer self.endGpuProfile(cmd_list, profile_index);

            const render_target = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];

            var rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(render_target, .RESOURCE_STATE_PRESENT, .RESOURCE_STATE_RENDER_TARGET),
            };

            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_CLEAR;

            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            const pipeline_id = IdLocal.init("tonemapper");
            const pipeline = self.getPSO(pipeline_id);

            graphics.cmdBindPipeline(cmd_list, pipeline);
            graphics.cmdBindDescriptorSet(cmd_list, 0, self.tonemapper_pass_descriptor_set);
            graphics.cmdDraw(cmd_list, 3, 0);
        }

        // UI Overlay
        {
            var rt_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.depth_buffer, .RESOURCE_STATE_SHADER_RESOURCE, .RESOURCE_STATE_DEPTH_READ),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, rt_barriers.len, @ptrCast(&rt_barriers));

            var bind_render_targets_desc = std.mem.zeroes(graphics.BindRenderTargetsDesc);
            bind_render_targets_desc.mRenderTargetCount = 1;
            bind_render_targets_desc.mRenderTargets[0] = std.mem.zeroes(graphics.BindRenderTargetDesc);
            bind_render_targets_desc.mRenderTargets[0].pRenderTarget = self.swap_chain.*.ppRenderTargets[self.swap_chain_image_index];
            bind_render_targets_desc.mRenderTargets[0].mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;
            bind_render_targets_desc.mDepthStencil = std.mem.zeroes(graphics.BindDepthTargetDesc);
            bind_render_targets_desc.mDepthStencil.pDepthStencil = self.depth_buffer;
            bind_render_targets_desc.mDepthStencil.mLoadAction = graphics.LoadActionType.LOAD_ACTION_LOAD;
            graphics.cmdBindRenderTargets(cmd_list, &bind_render_targets_desc);

            graphics.cmdSetViewport(cmd_list, 0.0, 0.0, @floatFromInt(self.window.frame_buffer_size[0]), @floatFromInt(self.window.frame_buffer_size[1]), 0.0, 1.0);
            graphics.cmdSetScissor(cmd_list, 0, 0, @intCast(self.window.frame_buffer_size[0]), @intCast(self.window.frame_buffer_size[1]));

            // UI Pass
            {
                const profile_index = self.startGpuProfile(cmd_list, "UI");
                defer self.endGpuProfile(cmd_list, profile_index);

                const trazy_zone1 = ztracy.ZoneNC(@src(), "UI Pass", 0x00_ff_00_00);
                defer trazy_zone1.End();

                self.ui_pass.render(cmd_list, render_view);
                self.im3d_pass.render(cmd_list, render_view);
            }

            // Debug Line Rendering: Draw Pass
            {
                const debug_line_args_buffer = self.getBuffer(self.debug_line_args_buffers[self.frame_index]);
                const line_vertex_buffer = self.getBuffer(self.debug_line_vertex_buffers[self.frame_index]);
                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(line_vertex_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_VERTEX_AND_CONSTANT_BUFFER),
                        graphics.BufferBarrier.init(debug_line_args_buffer, .RESOURCE_STATE_UNORDERED_ACCESS, .RESOURCE_STATE_INDIRECT_ARGUMENT),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }

                if (self.draw_debug_lines) {
                    const descriptor_set = self.debug_line_renderer_draw_descriptor_set;

                    {
                        var uniform_buffer = self.getBuffer(self.debug_frame_uniform_buffers[self.frame_index]);

                        var params: [1]graphics.DescriptorData = undefined;
                        params[0] = std.mem.zeroes(graphics.DescriptorData);
                        params[0].pName = "g_DebugFrame";
                        params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

                        graphics.updateDescriptorSet(self.renderer, self.frame_index, descriptor_set, @intCast(params.len), @ptrCast(&params));
                    }

                    const pipeline_id = IdLocal.init("debug_line_rendering_draw");
                    const pipeline = self.getPSO(pipeline_id);

                    const vertex_buffers = [_][*c]graphics.Buffer{line_vertex_buffer};
                    const vertex_buffer_strides = [_]u32{16};

                    graphics.cmdBindPipeline(cmd_list, pipeline);
                    graphics.cmdBindDescriptorSet(cmd_list, self.frame_index, descriptor_set);
                    graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&vertex_buffer_strides), null);
                    graphics.cmdExecuteIndirect(cmd_list, .INDIRECT_DRAW, 1, debug_line_args_buffer, 0, null, 0);
                }

                {
                    const buffer_barriers = [_]graphics.BufferBarrier{
                        graphics.BufferBarrier.init(debug_line_args_buffer, .RESOURCE_STATE_INDIRECT_ARGUMENT, .RESOURCE_STATE_COMMON),
                    };
                    graphics.cmdResourceBarrier(cmd_list, buffer_barriers.len, @constCast(&buffer_barriers), 0, null, 0, null);
                }
            }

            // ImGUI Pass
            if (self.render_imgui) {
                const profile_index = self.startGpuProfile(cmd_list, "ImGui");
                defer self.endGpuProfile(cmd_list, profile_index);

                const trazy_zone1 = ztracy.ZoneNC(@src(), "ImGUI Pass", 0x00_ff_00_00);
                defer trazy_zone1.End();

                zgui.backend.draw(cmd_list.*.mDx.pCmdList);
            } else {
                zgui.endFrame();
            }

            var output_barriers = [_]graphics.RenderTargetBarrier{
                graphics.RenderTargetBarrier.init(self.depth_buffer, .RESOURCE_STATE_DEPTH_READ, .RESOURCE_STATE_SHADER_RESOURCE),
            };
            graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, output_barriers.len, @ptrCast(&output_barriers));

            graphics.cmdBindRenderTargets(cmd_list, null);
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
                barrier.mCurrentState = .RESOURCE_STATE_RENDER_TARGET;
                barrier.mNewState = .RESOURCE_STATE_PRESENT;
                graphics.cmdResourceBarrier(cmd_list, 0, null, 0, null, 1, &barrier);
            }

            self.endGpuProfile(cmd_list, self.gpu_frame_profile_index);
            self.profiler.endFrame();
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

    fn updateStep(self: *Renderer, render_view: RenderView, cmd_list: [*c]graphics.Cmd) void {
        const trazy_zone = ztracy.ZoneNC(@src(), "Update", 0x00_ff_ff_00);
        defer trazy_zone.End();

        self.terrain_pass.update(render_view);
        self.static_geometry_pass.update(cmd_list);
        self.ui_pass.update();
    }

    fn drawRenderSettings(self: *Renderer) void {
        if (!self.render_imgui) {
            return;
        }

        zgui.setNextWindowSize(.{ .w = 600, .h = 1000, .cond = .first_use_ever });
        if (!zgui.begin("Renderer Settings", .{})) {
            zgui.end();
        } else {
            // GPU Profiler
            {
                if (zgui.collapsingHeader("Performance", .{ .default_open = true })) {
                    zgui.text("GPU Average time: {d}", .{self.getProfilerAvgTimeMs(self.gpu_frame_profile_index)});
                    zgui.text("Terrain Pass Average time: {d}", .{self.getProfilerAvgTimeMs(self.gpu_terrain_pass_profile_index)});
                    zgui.text("Geometry Pass Average time: {d}", .{self.getProfilerAvgTimeMs(self.gpu_geometry_pass_profile_index)});
                    zgui.text("GPU-Driven Pass Average time: {d}", .{self.getProfilerAvgTimeMs(self.gpu_gpu_driven_pass_profile_index)});
                }
            }

            // Player Camera Settings
            {
                var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
                var camera = camera_entity.getMut(fd.Camera).?;

                var camera_fov = std.math.radiansToDegrees(camera.fov);

                if (zgui.collapsingHeader("Camera", .{ .default_open = true })) {
                    if (zgui.dragFloat("FOV (deg)", .{ .v = &camera_fov, .speed = 1.0, .min = 10.0, .max = 100.0 })) {
                        camera.fov = std.math.degreesToRadians(camera_fov);
                    }
                }
            }

            // Renderer Settings
            {
                if (zgui.collapsingHeader("Renderer", .{ .default_open = true })) {
                    // _ = zgui.checkbox("VSync", .{ .v = &self.vsync_enabled });
                    _ = zgui.checkbox("Draw Debug Lines", .{ .v = &self.draw_debug_lines });
                    _ = zgui.dragFloat("Shadow Distance", .{ .v = &self.shadow_cascade_max_distance, .speed = 1.0, .min = 100.0, .max = 1500.0 });
                    zgui.text("Cascade 1: {d:.2}", .{self.shadow_cascade_depths[0]});
                    zgui.text("Cascade 2: {d:.2}", .{self.shadow_cascade_depths[1]});
                    zgui.text("Cascade 3: {d:.2}", .{self.shadow_cascade_depths[2]});
                    zgui.text("Cascade 4: {d:.2}", .{self.shadow_cascade_depths[3]});

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
                }
            }

            // TODO(gmodarelli)
            // self.terrain_pass.renderImGui();
            // self.dynamic_geometry_pass.renderImGui();
            self.static_geometry_pass.renderImGui();
            self.deferred_shading_pass.renderImGui();
            self.procedural_skybox_pass.renderImGui();
            self.water_pass.renderImGui();
            self.post_processing_pass.renderImGui();

            zgui.end();
        }
    }

    fn generateRenderView(self: *Renderer) RenderView {
        var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
        const camera_comps = camera_entity.getComps(struct {
            camera: *const fd.Camera,
            transform: *const fd.Transform,
        });

        var render_view = std.mem.zeroes(RenderView);
        render_view.view = zm.loadMat(camera_comps.camera.view[0..]);
        render_view.view_inverse = zm.inverse(render_view.view);
        render_view.projection = zm.loadMat(camera_comps.camera.projection[0..]);
        render_view.projection_inverse = zm.inverse(render_view.projection);
        render_view.view_projection = zm.loadMat(camera_comps.camera.view_projection[0..]);
        render_view.view_projection_inverse = zm.inverse(render_view.view_projection);
        render_view.position = camera_comps.transform.getPos00();
        render_view.fov = camera_comps.camera.fov;
        render_view.near_plane = @min(camera_comps.camera.near, camera_comps.camera.far);
        render_view.far_plane = @max(camera_comps.camera.near, camera_comps.camera.far);
        render_view.viewport = [2]f32{ @floatFromInt(self.window_width), @floatFromInt(self.window_height) };
        render_view.aspect = render_view.viewport[0] / render_view.viewport[1];
        render_view.frustum.init(render_view.view_projection);

        return render_view;
    }

    fn generateShadowViews(self: *Renderer) void {
        const min_point: f32 = 0;
        const max_point: f32 = 1;

        var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
        const camera_comps = camera_entity.getComps(struct {
            camera: *const fd.Camera,
            transform: *const fd.Transform,
        });

        const near_plane = @min(camera_comps.camera.near, camera_comps.camera.far);
        var far_plane = @max(camera_comps.camera.near, camera_comps.camera.far);
        far_plane = @min(self.shadow_cascade_max_distance, far_plane);

        const clip_range = far_plane - near_plane;
        const min_z = near_plane + min_point * clip_range;
        const max_z = near_plane + max_point * clip_range;

        var cascade_splits = std.mem.zeroes([cascades_max_count]f32);

        for (0..cascades_max_count) |i| {
            const p: f32 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(cascades_max_count));
            const log: f32 = min_z * std.math.pow(f32, max_z / min_z, p);
            const uniform: f32 = min_z + (max_z - min_z) * p;
            const d: f32 = self.shadow_pssm_factor * (log - uniform) + uniform;
            cascade_splits[i] = (d - near_plane) / clip_range;
        }

        const z_transform = zm.loadMat43(camera_comps.transform.matrix[0..]);
        const z_view = zm.inverse(z_transform);

        const z_projection =
            zm.perspectiveFovLh(
                camera_comps.camera.fov,
                @as(f32, @floatFromInt(self.window_width)) / @as(f32, @floatFromInt(self.window_height)),
                far_plane,
                near_plane,
            );

        const view_projection = zm.mul(z_view, z_projection);
        const view_projection_inverse = zm.inverse(view_projection);
        const frustum_corners_ws = [_]zm.Vec{
            transformVec3Coord(zm.Vec{ -1, -1, 1, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ -1, -1, 0, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ -1, 1, 1, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ -1, 1, 0, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ 1, 1, 1, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ 1, 1, 0, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ 1, -1, 1, 0 }, view_projection_inverse),
            transformVec3Coord(zm.Vec{ 1, -1, 0, 0 }, view_projection_inverse),
        };

        const shadow_caster_comps = self.getShadowCastingLight();
        const light_view = zm.inverse(zm.matFromQuat(shadow_caster_comps.rotation.asZM()));
        // const light_view = zm.inverse(zm.matFromQuat(zm.quatFromRollPitchYaw(std.math.pi * 0.25, 0.0, 0.0)));
        for (0..cascades_max_count) |i| {
            const previous_cascade_split = if (i == 0) min_point else cascade_splits[i - 1];
            const current_cascade_split = cascade_splits[i];

            // Compute the frustum corners for the cascade in view space
            const frustum_corners_vs = [_]zm.Vec{
                transformVec3Coord(zm.lerp(frustum_corners_ws[0], frustum_corners_ws[1], previous_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[0], frustum_corners_ws[1], current_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[2], frustum_corners_ws[3], previous_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[2], frustum_corners_ws[3], current_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[4], frustum_corners_ws[5], previous_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[4], frustum_corners_ws[5], current_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[6], frustum_corners_ws[7], previous_cascade_split), light_view),
                transformVec3Coord(zm.lerp(frustum_corners_ws[6], frustum_corners_ws[7], current_cascade_split), light_view),
            };

            var center = zm.Vec{ 0, 0, 0, 0 };
            for (frustum_corners_vs) |corner| {
                center = center + corner;
            }
            center = center / zm.splat(zm.Vec, @as(f32, @floatFromInt(frustum_corners_vs.len)));

            // Create a bounding sphere to maintain aspect in projection to avoid flickering when rotating
            var radius: f32 = 0;
            for (frustum_corners_vs) |corner| {
                const dist = zm.length3(corner - center)[0];
                radius = @max(dist, radius);
            }
            var extents_min = center - zm.splat(zm.Vec, radius);
            var extents_max = center + zm.splat(zm.Vec, radius);

            // Snap the cascade to the resolution of the shadowmap
            const extents = extents_max - extents_min;
            const texel_size = extents / zm.splat(zm.Vec, @floatFromInt(cascaded_shadow_resolution));
            extents_min = zm.floor(extents_min / texel_size) * texel_size;
            extents_max = zm.floor(extents_max / texel_size) * texel_size;
            center = (extents_min + extents_max) * zm.splat(zm.Vec, 0.5);

            // Z-bounds extents
            var extents_z = @abs(center[2] - extents_min[2]);
            extents_z = @max(extents_z, far_plane * 0.5);
            extents_min[2] = center[2] - extents_z;
            extents_max[2] = center[2] + extents_z;

            // const proj = zm.orthographicOffCenterLh(extents_min[0], extents_max[0], extents_max[1], extents_min[1], extents_max[2], extents_min[2]);
            const proj = orthographicOffCenterLh(extents_min[0], extents_max[0], extents_min[1], extents_max[1], extents_max[2], extents_min[2]);
            const proj_view = zm.mul(light_view, proj);

            self.shadow_views[i] = std.mem.zeroes(RenderView);
            self.shadow_views[i].view = light_view;
            self.shadow_views[i].view_inverse = zm.inverse(self.shadow_views[i].view);
            self.shadow_views[i].projection = proj;
            self.shadow_views[i].projection_inverse = zm.inverse(self.shadow_views[i].projection);
            self.shadow_views[i].view_projection = proj_view;
            self.shadow_views[i].view_projection_inverse = zm.inverse(self.shadow_views[i].view_projection);
            self.shadow_views[i].viewport = [2]f32{ @floatFromInt(cascaded_shadow_resolution), @floatFromInt(cascaded_shadow_resolution) };

            self.shadow_cascade_depths[i] = near_plane + current_cascade_split * (far_plane - near_plane);
        }

        var light_view_projections: [cascades_max_count][16]f32 = undefined;
        for (0..cascades_max_count) |cascade_index| {
            zm.storeMat(&light_view_projections[cascade_index], self.shadow_views[cascade_index].view_projection);
        }

        const data_slice = OpaqueSlice{
            .data = @ptrCast(light_view_projections[0..]),
            .size = @sizeOf([16]f32) * light_view_projections.len,
        };
        self.updateBuffer(data_slice, 0, [16]f32, self.light_matrix_buffer.buffer);
        self.light_matrix_buffer.element_count = @intCast(light_view_projections.len);
    }

    fn getShadowCastingLight(self: *Renderer) struct { rotation: *const fd.Rotation, light: *const fd.DirectionalLight } {
        const sun_entity = util.getSun(self.ecsu_world);
        const sun_comps = sun_entity.?.getComps(struct {
            rotation: *const fd.Rotation,
            light: *const fd.DirectionalLight,
        });

        const moon_entity = util.getMoon(self.ecsu_world);
        const moon_comps = moon_entity.?.getComps(struct {
            rotation: *const fd.Rotation,
            light: *const fd.DirectionalLight,
        });

        return .{
            .rotation = if (moon_comps.light.cast_shadows) moon_comps.rotation else sun_comps.rotation,
            .light = if (moon_comps.light.cast_shadows) moon_comps.light else sun_comps.light,
        };
    }

    fn orthographicOffCenterLh(left: f32, right: f32, bottom: f32, top: f32, near_z: f32, far_z: f32) zm.Mat {
        const rcp_width = 1.0 / (right - left);
        const rcp_height = 1.0 / (top - bottom);
        const rcp_zrange = 1.0 / (far_z - near_z);

        const a = -(left + right) * rcp_width;
        const b = -(top + bottom) * rcp_height;

        return .{
            zm.f32x4(2.0 * rcp_width, 0.0, 0.0, 0.0),
            zm.f32x4(0.0, 2.0 * rcp_height, 0.0, 0.0),
            zm.f32x4(0.0, 0.0, rcp_zrange, 0.0),
            zm.f32x4(a, b, -near_z * rcp_zrange, 1.0),
        };
    }

    pub fn registerRenderable(self: *Renderer, id: IdLocal, desc: RenderableDesc) void {
        var gpu_renderable_items = std.ArrayList(GpuRenderableItem).init(self.allocator);
        defer gpu_renderable_items.deinit();

        var renderable: Renderable = undefined;
        renderable.lods_count = desc.lods_count;
        renderable.gpu_instance_count = renderable.lods_count;

        var first_mesh = true;
        var renderable_bounds: geometry.BoundingBox = undefined;

        for (0..desc.lods_count) |lod_index| {
            const lod = &desc.lods[lod_index];
            const mesh_info = self.mesh_map.get(lod.mesh_id.hash).?;
            std.debug.assert(mesh_info.count == @as(u32, @intCast(lod.materials_count)));
            renderable.lods[lod_index].mesh_id = lod.mesh_id;
            renderable.lods[lod_index].screen_percentage_range[0] = lod.screen_percentage_range[0];
            renderable.lods[lod_index].screen_percentage_range[1] = lod.screen_percentage_range[1];
            renderable.lods[lod_index].materials_count = lod.materials_count;
            for (0..lod.materials_count) |material_index| {
                renderable.lods[lod_index].materials[material_index] = lod.materials[material_index];
            }
            renderable.gpu_instance_count += lod.materials_count;

            for (0..mesh_info.count) |mesh_index_offset| {
                const mesh = &self.meshes.items[mesh_info.index + mesh_index_offset];
                const material_index = self.getMaterialIndex(renderable.lods[lod_index].materials[mesh_index_offset]);

                var gpu_renderable_item: GpuRenderableItem = undefined;
                gpu_renderable_item.local_bounds_origin = mesh.bounds.center;
                gpu_renderable_item.local_bounds_extents = mesh.bounds.extents;
                gpu_renderable_item.screen_percentage_min = lod.screen_percentage_range[0];
                gpu_renderable_item.screen_percentage_max = lod.screen_percentage_range[1];
                gpu_renderable_item.mesh_index = @intCast(mesh_info.index + mesh_index_offset);
                gpu_renderable_item.material_index = @intCast(material_index);
                gpu_renderable_item._pad = [2]u32{ 73, 73 };

                gpu_renderable_items.append(gpu_renderable_item) catch unreachable;

                if (first_mesh) {
                    first_mesh = false;
                    renderable_bounds = mesh.bounds;
                } else {
                    renderable_bounds = geometry.mergeBoundingBoxes(renderable_bounds, mesh.bounds);
                }
            }
        }

        renderable.bounds_origin = renderable_bounds.center;
        renderable.bounds_extents = renderable_bounds.extents;

        self.renderable_map.put(id.hash, renderable) catch unreachable;
        self.renderable_item_map.put(id.hash, .{ .index = self.renderable_buffer.element_count, .count = @intCast(gpu_renderable_items.items.len) }) catch unreachable;

        // Upload renderable items to the GPU
        const data_slice = OpaqueSlice{
            .data = @ptrCast(gpu_renderable_items.items),
            .size = gpu_renderable_items.items.len * @sizeOf(GpuRenderableItem),
        };
        self.updateBuffer(data_slice, self.renderable_buffer.offset, GpuRenderableItem, self.renderable_buffer.buffer);
        self.renderable_buffer.offset += data_slice.size;
    }

    pub fn getRenderable(self: *Renderer, id: IdLocal) Renderable {
        return self.renderable_map.get(id.hash).?;
    }

    pub fn loadMaterial(self: *Renderer, material_id: IdLocal, material_data: UberShaderMaterialData) !void {
        var gpu_material: GpuMaterial = undefined;
        gpu_material.albedo_color[0] = material_data.base_color.r;
        gpu_material.albedo_color[1] = material_data.base_color.g;
        gpu_material.albedo_color[2] = material_data.base_color.b;
        gpu_material.albedo_color[3] = 1.0;
        gpu_material.uv_tiling_offset[0] = material_data.uv_tiling_offset[0];
        gpu_material.uv_tiling_offset[1] = material_data.uv_tiling_offset[1];
        gpu_material.uv_tiling_offset[2] = material_data.uv_tiling_offset[2];
        gpu_material.uv_tiling_offset[3] = material_data.uv_tiling_offset[3];
        gpu_material.roughness = material_data.roughness;
        gpu_material.metallic = material_data.metallic;
        gpu_material.normal_intensity = material_data.normal_intensity;
        gpu_material.emissive_strength = material_data.emissive_strength;
        gpu_material.albedo_texture_index = self.getTextureBindlessIndex(material_data.albedo);
        gpu_material.albedo_sampler_index = renderer_types.InvalidResourceIndex;
        gpu_material.emissive_texture_index = self.getTextureBindlessIndex(material_data.emissive);
        gpu_material.emissive_sampler_index = renderer_types.InvalidResourceIndex;
        gpu_material.normal_texture_index = self.getTextureBindlessIndex(material_data.normal);
        gpu_material.normal_sampler_index = renderer_types.InvalidResourceIndex;
        gpu_material.arm_texture_index = self.getTextureBindlessIndex(material_data.arm);
        gpu_material.arm_sampler_index = renderer_types.InvalidResourceIndex;
        if (material_data.random_color_feature_enabled) {
            gpu_material.random_color_feature_enabled = 1.0;
            gpu_material.random_color_noise_scale = material_data.random_color_noise_scale;
            gpu_material.random_color_gradient_texture_index = self.getTextureBindlessIndex(material_data.random_color_gradient);
        } else {
            gpu_material.random_color_feature_enabled = 0.0;
            gpu_material.random_color_noise_scale = 0.0;
            gpu_material.random_color_gradient_texture_index = renderer_types.InvalidResourceIndex;
        }

        if (self.pso_manager.getPsoBinId(material_data.gbuffer_pipeline_id.?)) |rasterizer_bin| {
            gpu_material.rasterizer_bin = rasterizer_bin;
        }

        const gpu_material_data_slice = OpaqueSlice{
            .data = @ptrCast(&gpu_material),
            .size = @sizeOf(GpuMaterial),
        };
        self.updateBuffer(gpu_material_data_slice, self.material_buffer.offset, GpuMaterial, self.material_buffer.buffer);
        self.material_buffer.offset += gpu_material_data_slice.size;

        const pipeline_ids = PassPipelineIds{
            .shadow_caster_pipeline_id = material_data.shadow_caster_pipeline_id,
            .gbuffer_pipeline_id = material_data.gbuffer_pipeline_id,
        };

        self.material_map.put(material_id.hash, .{ .index = self.material_buffer.element_count, .pipeline_ids = pipeline_ids, .alpha_test = material_data.alpha_test }) catch unreachable;
        self.material_buffer.element_count += 1;
    }

    pub fn getMaterialIndex(self: *Renderer, material_id: IdLocal) usize {
        const material_info = self.material_map.get(material_id.hash).?;
        return material_info.index;
    }

    pub fn getMaterialAlphaTest(self: *Renderer, material_id: IdLocal) bool {
        const material_data = self.material_map.get(material_id.hash);
        return material_data.?.alpha_test;
    }

    pub fn getMaterialPipelineIds(self: *Renderer, material_id: IdLocal) PassPipelineIds {
        const material_data = self.material_map.get(material_id.hash);
        return material_data.?.pipeline_ids;
    }

    pub fn loadMesh(self: *Renderer, path: []const u8, mesh_id: IdLocal) !void {
        var meshes_data = std.ArrayList(geometry.MeshData).init(self.allocator);
        defer meshes_data.deinit();

        var load_desc: geometry.MeshLoadDesc = undefined;
        load_desc.mesh_path = path;
        load_desc.allocator = self.allocator;
        load_desc.mesh_data = &meshes_data;
        geometry.loadMesh(&load_desc);

        const mesh_index: u32 = @intCast(self.meshes.items.len);
        const mesh_count: u32 = @intCast(meshes_data.items.len);
        self.mesh_map.put(mesh_id.hash, .{ .index = mesh_index, .count = mesh_count }) catch unreachable;

        // Upload the mesh
        var gpu_mesh_data = std.ArrayList(GPUMesh).init(self.allocator);
        defer gpu_mesh_data.deinit();

        for (meshes_data.items) |mesh_data| {
            var mesh = std.mem.zeroes(Mesh);
            const alignment: u64 = 16;

            var data_size: usize = 0;
            data_size += alignUp(mesh_data.indices.items.len * @sizeOf(u32), alignment);
            data_size += alignUp(mesh_data.positions_stream.items.len * @sizeOf([3]f32), alignment);
            data_size += alignUp(mesh_data.texcoords_stream.items.len * @sizeOf([2]f32), alignment);
            data_size += alignUp(mesh_data.normals_stream.items.len * @sizeOf([3]f32), alignment);
            data_size += alignUp(mesh_data.tangents_stream.items.len * @sizeOf([4]f32), alignment);
            data_size += alignUp(mesh_data.meshlets.items.len * @sizeOf(geometry.Meshlet), alignment);
            data_size += alignUp(mesh_data.meshlet_bounds.items.len * @sizeOf(geometry.MeshletBounds), alignment);
            data_size += alignUp(mesh_data.meshlet_triangles.items.len * @sizeOf(geometry.MeshletTriangle), alignment);
            data_size += alignUp(mesh_data.meshlet_vertices.items.len * @sizeOf(u32), alignment);

            const buffer_creation_desc = BufferCreationDesc{
                .bindless = true,
                .descriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW,
                .start_state = .RESOURCE_STATE_SHADER_RESOURCE,
                .size = data_size,
                .debug_name = "Geometry Buffer",
            };
            mesh.data_buffer = self.createBuffer(buffer_creation_desc);

            const buffer_data = self.allocator.alloc(u8, data_size) catch unreachable;
            defer self.allocator.free(buffer_data);

            var buffer_data_offset: usize = 0;
            const buffer_gpu_address = self.getBufferGPUAddress(mesh.data_buffer);
            // Positions
            {
                const stride = @sizeOf([3]f32);
                mesh.position_stream_location.location = buffer_gpu_address + buffer_data_offset;
                mesh.position_stream_location.elements = @intCast(mesh_data.positions_stream.items.len);
                mesh.position_stream_location.stride = @intCast(stride);
                mesh.position_stream_location.offset_from_start = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.positions_stream.items.ptr), mesh_data.positions_stream.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.positions_stream.items.len * stride, alignment);
            }
            // Texcoords
            {
                const stride = @sizeOf([2]f32);
                mesh.texcoord_stream_location.location = buffer_gpu_address + buffer_data_offset;
                mesh.texcoord_stream_location.elements = @intCast(mesh_data.texcoords_stream.items.len);
                mesh.texcoord_stream_location.stride = @intCast(stride);
                mesh.texcoord_stream_location.offset_from_start = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.texcoords_stream.items.ptr), mesh_data.texcoords_stream.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.texcoords_stream.items.len * stride, alignment);
            }
            // Normals
            {
                const stride = @sizeOf([3]f32);
                mesh.normal_stream_location.location = buffer_gpu_address + buffer_data_offset;
                mesh.normal_stream_location.elements = @intCast(mesh_data.normals_stream.items.len);
                mesh.normal_stream_location.stride = @intCast(stride);
                mesh.normal_stream_location.offset_from_start = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.normals_stream.items.ptr), mesh_data.normals_stream.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.normals_stream.items.len * stride, alignment);
            }
            // Tangents
            {
                const stride = @sizeOf([4]f32);
                mesh.tangent_stream_location.location = buffer_gpu_address + buffer_data_offset;
                mesh.tangent_stream_location.elements = @intCast(mesh_data.tangents_stream.items.len);
                mesh.tangent_stream_location.stride = @intCast(stride);
                mesh.tangent_stream_location.offset_from_start = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.tangents_stream.items.ptr), mesh_data.tangents_stream.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.tangents_stream.items.len * stride, alignment);
            }
            // Indices
            {
                // TODO
                // const small_indices = mesh_data.positions_stream.items.len < std.math.maxInt(u16);
                // const index_size = if (small_indices) @sizeOf(u16) else @sizeOf(u32);
                const stride = @sizeOf(u32);
                mesh.indices_location.location = buffer_gpu_address + buffer_data_offset;
                mesh.indices_location.elements = @intCast(mesh_data.indices.items.len);
                mesh.indices_location.offset_from_start = @intCast(buffer_data_offset);
                mesh.indices_location.index_type = .INDEX_TYPE_UINT32;

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.indices.items.ptr), mesh_data.indices.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.indices.items.len * stride, alignment);
            }

            // Meshlets
            {
                const stride = @sizeOf(geometry.Meshlet);
                mesh.meshlets_location = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.meshlets.items.ptr), mesh_data.meshlets.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.meshlets.items.len * stride, alignment);
                mesh.meshlet_count = @intCast(mesh_data.meshlets.items.len);
            }

            // Meshlet Vertices
            {
                const stride = @sizeOf(u32);
                mesh.meshlet_vertices_location = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.meshlet_vertices.items.ptr), mesh_data.meshlet_vertices.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.meshlet_vertices.items.len * stride, alignment);
            }

            // Meshlet Triangles
            {
                const stride = @sizeOf(geometry.MeshletTriangle);
                mesh.meshlet_triangles_location = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.meshlet_triangles.items.ptr), mesh_data.meshlet_triangles.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.meshlet_triangles.items.len * stride, alignment);
            }

            // Meshlet Bounds
            {
                const stride = @sizeOf(geometry.MeshletBounds);
                mesh.meshlet_bounds_location = @intCast(buffer_data_offset);

                util.memcpy(@ptrCast(buffer_data), @ptrCast(mesh_data.meshlet_bounds.items.ptr), mesh_data.meshlet_bounds.items.len * stride, .{ .dst_offset = buffer_data_offset });
                buffer_data_offset += alignUp(mesh_data.meshlet_bounds.items.len * stride, alignment);
            }

            mesh.bounds.center = mesh_data.bounds.center;
            mesh.bounds.extents = mesh_data.bounds.extents;

            const data_slice = OpaqueSlice{
                .data = @ptrCast(buffer_data),
                .size = data_size,
            };
            self.updateBuffer(data_slice, 0, u8, mesh.data_buffer);
            self.meshes.append(mesh) catch unreachable;

            const gpu_mesh = GPUMesh{
                .data_buffer = self.getBufferBindlessIndex(mesh.data_buffer),
                .index_byte_size = 4, // TODO
                .indices_offset = @intCast(mesh.indices_location.offset_from_start),
                .positions_offset = @intCast(mesh.position_stream_location.offset_from_start),
                .texcoords_offset = @intCast(mesh.texcoord_stream_location.offset_from_start),
                .tangents_offset = @intCast(mesh.tangent_stream_location.offset_from_start),
                .normals_offset = @intCast(mesh.normal_stream_location.offset_from_start),
                .meshlet_offset = mesh.meshlets_location,
                .meshlet_bounds_offset = mesh.meshlet_bounds_location,
                .meshlet_triangle_offset = mesh.meshlet_triangles_location,
                .meshlet_vertex_offset = mesh.meshlet_vertices_location,
                .meshlet_count = mesh.meshlet_count,
            };

            gpu_mesh_data.append(gpu_mesh) catch unreachable;
        }

        const gpu_mesh_data_slice = OpaqueSlice{
            .data = @ptrCast(gpu_mesh_data.items),
            .size = @sizeOf(GPUMesh) * gpu_mesh_data.items.len,
        };
        self.updateBuffer(gpu_mesh_data_slice, self.mesh_buffer.offset, GPUMesh, self.mesh_buffer.buffer);
        self.mesh_buffer.offset += gpu_mesh_data_slice.size;
    }

    pub fn getMeshInfo(self: *Renderer, mesh_id: IdLocal) MeshInfo {
        return self.mesh_map.get(mesh_id.hash).?;
    }

    fn alignUp(value: u64, alignment: u64) u64 {
        return (value + (alignment - 1)) & ~(alignment - 1);
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

    pub fn loadTextureFromMemory(self: *Renderer, width: u32, height: u32, format: graphics.TinyImageFormat, data_slice: OpaqueSlice, debug_name: [*:0]const u8) TextureHandle {
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

    pub fn createBuffer(self: *Renderer, desc: BufferCreationDesc) BufferHandle {
        std.debug.assert(desc.size > 0);

        var buffer: [*c]graphics.Buffer = null;

        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.mSize = desc.size;
        load_desc.mDesc.pName = @constCast(desc.debug_name.ptr);
        load_desc.mDesc.mDescriptors = desc.descriptors;

        if (desc.bindless) {
            std.debug.assert(!desc.cpu_accessible);
            load_desc.mDesc.bBindless = true;
            load_desc.mDesc.mFlags = .BUFFER_CREATION_FLAG_SHADER_DEVICE_ADDRESS;
            load_desc.mDesc.mElementCount = @intCast(desc.size / @sizeOf(u32));
        } else {
            std.debug.assert(desc.element_size > 0);
            load_desc.mDesc.mElementCount = @intCast(desc.size / desc.element_size);
        }

        load_desc.mDesc.mMemoryUsage = .RESOURCE_MEMORY_USAGE_GPU_ONLY;
        if (desc.cpu_accessible) {
            load_desc.mDesc.mMemoryUsage = .RESOURCE_MEMORY_USAGE_CPU_TO_GPU;
        }

        if (desc.data) |data| {
            load_desc.pData = data;
        }

        load_desc.ppBuffer = &buffer;

        var token: resource_loader.SyncToken = 0;
        resource_loader.addResource(@ptrCast(&load_desc), &token);
        resource_loader.waitForToken(&token);

        const handle: BufferHandle = self.buffer_pool.add(.{ .buffer = buffer }) catch unreachable;
        return handle;
    }

    // Helper buffer creation functions
    pub fn createBindlessBuffer(self: *Renderer, size: u64, debug_name: []const u8) BufferHandle {
        const buffer_creation_desc = BufferCreationDesc{
            .bindless = true,
            .descriptors = .DESCRIPTOR_TYPE_BUFFER_RAW,
            .start_state = .RESOURCE_STATE_COMMON,
            .size = size,
            .debug_name = debug_name,
        };

        return self.createBuffer(buffer_creation_desc);
    }

    pub fn createReadWriteBindlessBuffer(self: *Renderer, size: u64, debug_name: []const u8) BufferHandle {
        const buffer_creation_desc = BufferCreationDesc{
            .bindless = true,
            .descriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits },
            .start_state = .RESOURCE_STATE_COMMON,
            .size = size,
            .debug_name = debug_name,
        };

        return self.createBuffer(buffer_creation_desc);
    }

    pub fn createIndexBuffer(self: *Renderer, initial_data: OpaqueSlice, index_size: u32, cpu_accessible: bool, debug_name: []const u8) BufferHandle {
        const buffer_creation_desc = BufferCreationDesc{
            .bindless = false,
            .cpu_accessible = cpu_accessible,
            .descriptors = .DESCRIPTOR_TYPE_INDEX_BUFFER,
            .start_state = .RESOURCE_STATE_COMMON,
            .size = initial_data.size,
            .element_size = @intCast(index_size),
            .data = initial_data.data,
            .debug_name = debug_name,
        };

        return self.createBuffer(buffer_creation_desc);
    }

    pub fn createVertexBuffer(self: *Renderer, initial_data: OpaqueSlice, vertex_size: u32, cpu_accessible: bool, debug_name: []const u8) BufferHandle {
        const buffer_creation_desc = BufferCreationDesc{
            .bindless = false,
            .cpu_accessible = cpu_accessible,
            .descriptors = .DESCRIPTOR_TYPE_VERTEX_BUFFER,
            .start_state = .RESOURCE_STATE_COMMON,
            .size = initial_data.size,
            .element_size = @intCast(vertex_size),
            .data = initial_data.data,
            .debug_name = debug_name,
        };

        return self.createBuffer(buffer_creation_desc);
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

    pub fn createStructuredBuffer(self: *Renderer, initial_data: OpaqueSlice, debug_name: [:0]const u8) BufferHandle {
        var buffer: [*c]graphics.Buffer = null;

        var load_desc = std.mem.zeroes(resource_loader.BufferLoadDesc);
        load_desc.mDesc.pName = debug_name;
        load_desc.mDesc.bBindless = false;
        load_desc.mDesc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits };
        load_desc.mDesc.mFlags = graphics.BufferCreationFlags.BUFFER_CREATION_FLAG_SHADER_DEVICE_ADDRESS;
        load_desc.mDesc.mMemoryUsage = graphics.ResourceMemoryUsage.RESOURCE_MEMORY_USAGE_GPU_ONLY;
        // NOTE(gmodarelli): The persistent SRV uses a R32_TYPELESS representation, so we need to provide an element count in terms of 32bit data
        load_desc.mDesc.mElementCount = @intCast(initial_data.size / @sizeOf(u32));
        load_desc.mDesc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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

    pub fn updateBuffer(self: *Renderer, data: OpaqueSlice, dest_offset: u64, comptime T: type, handle: BufferHandle) void {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        _ = T;

        var update_desc = std.mem.zeroes(resource_loader.BufferUpdateDesc);
        update_desc.pBuffer = @ptrCast(buffer);
        update_desc.mDstOffset = dest_offset;
        resource_loader.beginUpdateResource(&update_desc);
        util.memcpy(update_desc.pMappedData.?, data.data.?, data.size, .{});
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

    pub fn getBufferGPUAddress(self: *Renderer, handle: BufferHandle) u64 {
        const buffer = self.buffer_pool.getColumn(handle, .buffer) catch unreachable;
        return @intCast(buffer.*.mDx.mGpuAddress);
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
        desc.mEnableVsync = false; // self.vsync_enabled;
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
            rt_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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
            texture_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
            texture_desc.mDescriptors = .{ .bits = graphics.DescriptorType.DESCRIPTOR_TYPE_TEXTURE.bits | graphics.DescriptorType.DESCRIPTOR_TYPE_RW_TEXTURE.bits };
            texture_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            texture_desc.bBindless = false;

            texture_desc.pName = "Linear Depth 0";
            self.linear_depth_buffers[0] = self.createTexture(texture_desc);

            texture_desc.pName = "Linear Depth 1";
            self.linear_depth_buffers[1] = self.createTexture(texture_desc);
        }

        // Shadow Buffers
        for (0..cascades_max_count) |i| {
            var rt_name_buffer: [256]u8 = undefined;
            const rt_name = std.fmt.bufPrintZ(
                rt_name_buffer[0..rt_name_buffer.len],
                "Shadow Depth Buffer {d}",
                .{i},
            ) catch unreachable;

            var rt_desc = std.mem.zeroes(graphics.RenderTargetDesc);
            rt_desc.pName = rt_name;
            rt_desc.mArraySize = 1;
            rt_desc.mClearValue.__struct_field3.depth = 0.0;
            rt_desc.mClearValue.__struct_field3.stencil = 0;
            rt_desc.mDepth = 1;
            rt_desc.mFormat = graphics.TinyImageFormat.D32_SFLOAT;
            rt_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
            rt_desc.mWidth = cascaded_shadow_resolution;
            rt_desc.mHeight = cascaded_shadow_resolution;
            rt_desc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            rt_desc.mSampleQuality = 0;
            rt_desc.mFlags = graphics.TextureCreationFlags.TEXTURE_CREATION_FLAG_ON_TILE;
            graphics.addRenderTarget(self.renderer, &rt_desc, &self.shadow_depth_buffers[i]);
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
                rt_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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
                rt_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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
                rt_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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
            rt_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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

        for (0..cascades_max_count) |i| {
            graphics.removeRenderTarget(self.renderer, self.shadow_depth_buffers[i]);
        }

        graphics.removeRenderTarget(self.renderer, self.gbuffer_0);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_1);
        graphics.removeRenderTarget(self.renderer, self.gbuffer_2);

        graphics.removeRenderTarget(self.renderer, self.scene_color);
        graphics.removeRenderTarget(self.renderer, self.scene_color_copy);

        self.destroyBloomUAVs();
    }

    fn createBloomUAVs(self: *Renderer) void {
        // Common settings
        var texture_desc = std.mem.zeroes(graphics.TextureDesc);
        texture_desc.mDepth = 1;
        texture_desc.mArraySize = 1;
        texture_desc.mMipLevels = 1;
        texture_desc.mStartState = .RESOURCE_STATE_SHADER_RESOURCE;
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

    fn createResolutionIndependentRenderTargets(self: *Renderer) void {
        _ = self;
    }

    fn destroyResolutionIndependentRenderTargets(self: *Renderer) void {
        _ = self;
    }

    fn createCompositeSDRDescriptorSet(self: *Renderer) void {
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.pRootSignature = self.getRootSignature(IdLocal.init("tonemapper"));
        desc.mMaxSets = data_buffer_count;

        graphics.addDescriptorSet(self.renderer, &desc, @ptrCast(&self.tonemapper_pass_descriptor_set));
    }

    fn prepareCompositeSDRDescriptorSet(self: *Renderer) void {
        for (0..data_buffer_count) |frame_index| {
            var params: [1]graphics.DescriptorData = undefined;

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "HDRBuffer";
            params[0].__union_field3.ppTextures = @ptrCast(&self.scene_color.*.pTexture);

            graphics.updateDescriptorSet(self.renderer, @intCast(frame_index), self.tonemapper_pass_descriptor_set, params.len, @ptrCast(&params));
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
            var params: [3]graphics.DescriptorData = undefined;

            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "GBuffer0";
            params[0].__union_field3.ppTextures = @ptrCast(&self.gbuffer_0.*.pTexture);
            params[1] = std.mem.zeroes(graphics.DescriptorData);
            params[1].pName = "GBuffer1";
            params[1].__union_field3.ppTextures = @ptrCast(&self.gbuffer_1.*.pTexture);
            params[2] = std.mem.zeroes(graphics.DescriptorData);
            params[2].pName = "GBuffer2";
            params[2].__union_field3.ppTextures = @ptrCast(&self.gbuffer_2.*.pTexture);

            graphics.updateDescriptorSet(self.renderer, @intCast(frame_index), self.buffers_visualization_descriptor_set, params.len, @ptrCast(&params));
        }
    }
};

// ██████╗ ██╗   ██╗███████╗███████╗███████╗██████╗ ███████╗
// ██╔══██╗██║   ██║██╔════╝██╔════╝██╔════╝██╔══██╗██╔════╝
// ██████╔╝██║   ██║█████╗  █████╗  █████╗  ██████╔╝███████╗
// ██╔══██╗██║   ██║██╔══╝  ██╔══╝  ██╔══╝  ██╔══██╗╚════██║
// ██████╔╝╚██████╔╝██║     ██║     ███████╗██║  ██║███████║
// ╚═════╝  ╚═════╝ ╚═╝     ╚═╝     ╚══════╝╚═╝  ╚═╝╚══════╝
//

pub const BufferCreationDesc = struct {
    bindless: bool = false,
    cpu_accessible: bool = false,
    descriptors: graphics.DescriptorType = undefined,
    start_state: graphics.ResourceState = .RESOURCE_STATE_UNDEFINED,
    size: u64 = 0,
    element_size: u64 = 0,
    data: ?*const anyopaque = null,
    debug_name: []const u8,
};

pub const ElementBindlessBuffer = struct {
    mutex: std.Thread.Mutex = undefined,
    buffer: BufferHandle = undefined,
    stride: u64 = 0,
    size: u64 = 0,
    offset: u64 = 0,
    element_count: u32 = 0,

    pub fn init(self: *@This(), renderer: *Renderer, elements_count_limit: u64, stride: usize, uav: bool, debug_name: []const u8) void {
        self.mutex = std.Thread.Mutex{};
        self.size = elements_count_limit * stride;
        self.stride = stride;
        self.offset = 0;
        self.element_count = 0;

        var buffer_creation_desc = BufferCreationDesc{
            .bindless = true,
            .descriptors = graphics.DescriptorType.DESCRIPTOR_TYPE_BUFFER_RAW,
            .start_state = .RESOURCE_STATE_SHADER_RESOURCE,
            .size = self.size,
            .debug_name = debug_name,
        };

        if (uav) {
            buffer_creation_desc.descriptors.bits |= graphics.DescriptorType.DESCRIPTOR_TYPE_RW_BUFFER_RAW.bits;
        }

        self.buffer = renderer.createBuffer(buffer_creation_desc);
    }
};

// ██╗   ██╗██╗███████╗██╗    ██╗███████╗
// ██║   ██║██║██╔════╝██║    ██║██╔════╝
// ██║   ██║██║█████╗  ██║ █╗ ██║███████╗
// ╚██╗ ██╔╝██║██╔══╝  ██║███╗██║╚════██║
//  ╚████╔╝ ██║███████╗╚███╔███╔╝███████║
//   ╚═══╝  ╚═╝╚══════╝ ╚══╝╚══╝ ╚══════╝

pub const RenderView = struct {
    view: zm.Mat,
    view_inverse: zm.Mat,
    projection: zm.Mat,
    projection_inverse: zm.Mat,
    view_projection: zm.Mat,
    view_projection_inverse: zm.Mat,

    position: [3]f32,
    fov: f32,
    near_plane: f32,
    far_plane: f32,
    viewport: [2]f32,
    aspect: f32,
    frustum: renderer_types.Frustum,
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗  █████╗ ██████╗ ██╗     ███████╗███████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔══██╗██║     ██╔════╝██╔════╝
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝███████║██████╔╝██║     █████╗  ███████╗
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗██╔══██║██╔══██╗██║     ██╔══╝  ╚════██║
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║██║  ██║██████╔╝███████╗███████╗███████║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝╚══════╝

const materials_per_renderable_max_count: u32 = 16;
const lods_per_renderable_max_count: u32 = 4;

pub const RenderableDesc = struct {
    lods: [lods_per_renderable_max_count]RenderableLod,
    lods_count: u32,
};

pub const RenderableLod = struct {
    mesh_id: IdLocal,
    materials: [materials_per_renderable_max_count]IdLocal,
    materials_count: u32,
    screen_percentage_range: [2]f32,
};

const Renderable = struct {
    lods: [lods_per_renderable_max_count]RenderableLod,
    lods_count: u32,
    gpu_instance_count: u32,
    bounds_origin: [3]f32,
    bounds_extents: [3]f32,
};

const RenderableHashMap = std.AutoHashMap(u64, Renderable);

const GpuRenderableItem = struct {
    local_bounds_origin: [3]f32,
    screen_percentage_min: f32,
    local_bounds_extents: [3]f32,
    screen_percentage_max: f32,
    mesh_index: u32,
    material_index: u32,
    _pad: [2]u32,
};

const RenderableToRenderableItems = std.AutoHashMap(u64, struct { index: usize, count: u32 });

// ███╗   ███╗███████╗███████╗██╗  ██╗███████╗███████╗
// ████╗ ████║██╔════╝██╔════╝██║  ██║██╔════╝██╔════╝
// ██╔████╔██║█████╗  ███████╗███████║█████╗  ███████╗
// ██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║██╔══╝  ╚════██║
// ██║ ╚═╝ ██║███████╗███████║██║  ██║███████╗███████║
// ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝

const VertexBufferView = struct {
    location: u64,
    elements: u32,
    stride: u32,
    offset_from_start: u32,
};

const IndexBufferView = struct {
    location: u64,
    elements: u32,
    offset_from_start: u32,
    index_type: graphics.IndexType,
};

pub const Mesh = struct {
    data_buffer: BufferHandle = undefined,

    position_stream_location: VertexBufferView = undefined,
    texcoord_stream_location: VertexBufferView = undefined,
    normal_stream_location: VertexBufferView = undefined,
    tangent_stream_location: VertexBufferView = undefined,
    indices_location: IndexBufferView = undefined,
    bounds: geometry.BoundingBox = undefined,

    meshlets_location: u32 = std.math.maxInt(u32),
    meshlet_vertices_location: u32 = std.math.maxInt(u32),
    meshlet_triangles_location: u32 = std.math.maxInt(u32),
    meshlet_bounds_location: u32 = std.math.maxInt(u32),
    meshlet_count: u32 = 0,
};

const GPUMesh = struct {
    data_buffer: u32,
    positions_offset: u32,
    normals_offset: u32,
    texcoords_offset: u32,
    tangents_offset: u32,
    indices_offset: u32,
    index_byte_size: u32,
    meshlet_offset: u32,
    meshlet_vertex_offset: u32,
    meshlet_triangle_offset: u32,
    meshlet_bounds_offset: u32,
    meshlet_count: u32,
};

pub const MeshInfo = struct {
    index: u32,
    count: u32,
};
const MeshHashMap = std.AutoHashMap(u64, MeshInfo);

// ███╗   ███╗ █████╗ ████████╗███████╗██████╗ ██╗ █████╗ ██╗     ███████╗
// ████╗ ████║██╔══██╗╚══██╔══╝██╔════╝██╔══██╗██║██╔══██╗██║     ██╔════╝
// ██╔████╔██║███████║   ██║   █████╗  ██████╔╝██║███████║██║     ███████╗
// ██║╚██╔╝██║██╔══██║   ██║   ██╔══╝  ██╔══██╗██║██╔══██║██║     ╚════██║
// ██║ ╚═╝ ██║██║  ██║   ██║   ███████╗██║  ██║██║██║  ██║███████╗███████║
// ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝╚══════╝╚══════╝

const GpuMaterial = struct {
    albedo_color: [4]f32,
    uv_tiling_offset: [4]f32,
    roughness: f32,
    metallic: f32,
    normal_intensity: f32,
    emissive_strength: f32,
    albedo_texture_index: u32,
    albedo_sampler_index: u32,
    emissive_texture_index: u32,
    emissive_sampler_index: u32,
    normal_texture_index: u32,
    normal_sampler_index: u32,
    arm_texture_index: u32,
    arm_sampler_index: u32,

    random_color_feature_enabled: f32 = 0,
    random_color_noise_scale: f32 = 0,
    random_color_gradient_texture_index: u32 = std.math.maxInt(u32),
    _pad0: u32,

    rasterizer_bin: u32,
    _pad1: [3]u32 = .{ 42, 42, 42 },
};

const MaterialMap = std.AutoHashMap(u64, struct { index: usize, pipeline_ids: PassPipelineIds, alpha_test: bool });

pub const SurfaceType = enum {
    @"opaque",
    cutout,
};

pub const ShadingTechnique = enum {
    gbuffer,
    shadow_caster,
};

pub const UberShaderMaterialData = struct {
    // Techniques
    gbuffer_pipeline_id: ?IdLocal,
    shadow_caster_pipeline_id: ?IdLocal,

    // Surface Type
    alpha_test: bool,

    // Basic PBR Surface Data
    base_color: fd.ColorRGB,
    uv_tiling_offset: [4]f32,
    metallic: f32,
    roughness: f32,
    normal_intensity: f32,
    emissive_strength: f32,
    albedo: TextureHandle,
    normal: TextureHandle,
    arm: TextureHandle,
    emissive: TextureHandle,

    // Random color variation
    random_color_feature_enabled: bool = false,
    random_color_noise_scale: f32 = 0,
    random_color_gradient: TextureHandle = TextureHandle.nil,

    pub fn init() UberShaderMaterialData {
        return initNoTexture(fd.ColorRGB.init(1, 1, 1), 0.5, 0.0);
    }

    pub fn initNoTexture(base_color: fd.ColorRGB, roughness: f32, metallic: f32) UberShaderMaterialData {
        return .{
            .gbuffer_pipeline_id = null,
            .shadow_caster_pipeline_id = null,
            .alpha_test = false,
            .base_color = base_color,
            .uv_tiling_offset = .{ 1.0, 1.0, 0.0, 0.0 },
            .roughness = roughness,
            .metallic = metallic,
            .normal_intensity = 1.0,
            .emissive_strength = 1.0,
            .albedo = TextureHandle.nil,
            .normal = TextureHandle.nil,
            .arm = TextureHandle.nil,
            .emissive = TextureHandle.nil,
            .random_color_feature_enabled = false,
        };
    }
};

pub const PassPipelineIds = struct {
    shadow_caster_pipeline_id: ?IdLocal,
    gbuffer_pipeline_id: ?IdLocal,
};

// ██╗     ███████╗ ██████╗  █████╗  ██████╗██╗   ██╗    ███╗   ███╗███████╗███████╗██╗  ██╗███████╗███████╗
// ██║     ██╔════╝██╔════╝ ██╔══██╗██╔════╝╚██╗ ██╔╝    ████╗ ████║██╔════╝██╔════╝██║  ██║██╔════╝██╔════╝
// ██║     █████╗  ██║  ███╗███████║██║      ╚████╔╝     ██╔████╔██║█████╗  ███████╗███████║█████╗  ███████╗
// ██║     ██╔══╝  ██║   ██║██╔══██║██║       ╚██╔╝      ██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║██╔══╝  ╚════██║
// ███████╗███████╗╚██████╔╝██║  ██║╚██████╗   ██║       ██║ ╚═╝ ██║███████╗███████║██║  ██║███████╗███████║
// ╚══════╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝   ╚═╝       ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝

pub const GpuMeshIndices = struct {
    count: u32,
    indices: [geometry.sub_mesh_max_count]u32,
};

pub const LegacyMesh = struct {
    geometry: [*c]resource_loader.Geometry,
    data: [*c]resource_loader.GeometryData,
    buffer_layout_desc: resource_loader.GeometryBufferLayoutDesc,
    vertex_layout_id: IdLocal,
    loaded: bool,
};

const LegacyMeshPool = Pool(16, 16, LegacyMesh, struct { mesh: LegacyMesh });
pub const LegacyMeshHandle = LegacyMeshPool.Handle;

const TexturePool = Pool(16, 16, graphics.Texture, struct { texture: [*c]graphics.Texture });
pub const TextureHandle = TexturePool.Handle;

const BufferPool = Pool(16, 16, graphics.Buffer, struct { buffer: [*c]graphics.Buffer });
pub const BufferHandle = BufferPool.Handle;

pub inline fn transformVec3Coord(v: zm.Vec, m: zm.Mat) zm.Vec {
    const z = zm.splat(zm.F32x4, v[2]);
    const y = zm.splat(zm.F32x4, v[1]);
    const x = zm.splat(zm.F32x4, v[0]);

    var result = zm.mulAdd(z, m[2], m[3]);
    result = zm.mulAdd(y, m[1], result);
    result = zm.mulAdd(x, m[0], result);

    result[0] /= result[3];
    result[1] /= result[3];
    result[2] /= result[3];
    result[3] = 1.0;
    return result;
}
