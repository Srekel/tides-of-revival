const std = @import("std");

const IdLocal = @import("../core/core.zig").IdLocal;
const Renderer = @import("renderer.zig").Renderer;
const zforge = @import("zforge");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const Pool = @import("zpool").Pool;

pub const opaque_pipelines = [_]IdLocal{
    IdLocal.init("lit_gbuffer_opaque"),
    IdLocal.init("lit_shadow_caster_opaque"),
};

pub const cutout_pipelines = [_]IdLocal{
    IdLocal.init("lit_gbuffer_cutout"),
    IdLocal.init("lit_shadow_caster_cutout"),
};

const PSOPool = Pool(16, 16, graphics.Shader, struct { shader: [*c]graphics.Shader, root_signature: [*c]graphics.RootSignature, pipeline: [*c]graphics.Pipeline });
const PSOHandle = PSOPool.Handle;
const PSOMap = std.AutoHashMap(IdLocal, PSOHandle);
const BlendStates = std.AutoHashMap(IdLocal, graphics.BlendStateDesc);

const GraphicsPipelineDesc = struct {
    id: IdLocal = undefined,
    vert_shader_name: []const u8 = undefined,
    frag_shader_name: ?[]const u8 = null,
    geom_shader_name: ?[]const u8 = null,
    topology: graphics.PrimitiveTopology = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST,
    vertex_layout_id: ?IdLocal = null,
    render_targets: []graphics.TinyImageFormat = undefined,
    rasterizer_state: ?graphics.RasterizerStateDesc = null,
    depth_state: ?graphics.DepthStateDesc = null,
    depth_format: ?graphics.TinyImageFormat = null,
    blend_state: ?graphics.BlendStateDesc = null,
    sampler_ids: []IdLocal = undefined,
};

const MeshPipelineDesc = struct {
    id: IdLocal = undefined,
    mesh_shader_name: []const u8 = undefined,
    ampl_shader_name: ?[]const u8 = null,
    frag_shader_name: ?[]const u8 = null,
    render_targets: []graphics.TinyImageFormat = undefined,
    rasterizer_state: ?graphics.RasterizerStateDesc = null,
    depth_state: ?graphics.DepthStateDesc = null,
    depth_format: ?graphics.TinyImageFormat = null,
    blend_state: ?graphics.BlendStateDesc = null,
    sampler_ids: []IdLocal = undefined,
};

pub const PsoBin = struct {
    gbuffer_id: IdLocal,
    shadow_caster_id: IdLocal = undefined,
};

pub const pso_bins_max_count: u32 = 8;

pub const PSOManager = struct {
    allocator: std.mem.Allocator = undefined,
    renderer: *Renderer = undefined,

    pso_pool: PSOPool = undefined,
    pso_map: PSOMap = undefined,
    pso_bins: std.ArrayList(PsoBin) = undefined,
    blend_states: BlendStates = undefined,
    samplers: StaticSamplers = undefined,

    pub fn init(self: *PSOManager, renderer: *Renderer, allocator: std.mem.Allocator) !void {
        std.debug.assert(renderer.renderer != null);

        self.allocator = allocator;
        self.renderer = renderer;
        self.pso_pool = PSOPool.initMaxCapacity(allocator) catch unreachable;
        self.pso_map = PSOMap.init(allocator);
        self.pso_bins = std.ArrayList(PsoBin).init(self.allocator);
        self.blend_states = BlendStates.init(allocator);
        self.samplers = StaticSamplers.create(renderer.renderer, allocator);

        self.createBlendStates();
    }

    pub fn exit(self: *PSOManager) void {
        var shader_handles = self.pso_pool.liveHandles();
        while (shader_handles.next()) |handle| {
            const pipeline = self.pso_pool.getColumn(handle, .pipeline) catch unreachable;
            graphics.removePipeline(self.renderer.renderer, pipeline);

            const root_signature = self.pso_pool.getColumn(handle, .root_signature) catch unreachable;
            graphics.removeRootSignature(self.renderer.renderer, root_signature);

            const shader = self.pso_pool.getColumn(handle, .shader) catch unreachable;
            graphics.removeShader(self.renderer.renderer, shader);
        }
        self.pso_pool.deinit();
        self.pso_map.deinit();
        self.pso_bins.deinit();
        self.blend_states.deinit();

        self.samplers.exit(self.renderer.renderer);
    }

    fn createBlendStates(self: *PSOManager) void {
        {
            const id = IdLocal.init("bs_transparent");
            var desc = std.mem.zeroes(graphics.BlendStateDesc);
            desc.mSrcFactors[0] = graphics.BlendConstant.BC_SRC_ALPHA;
            desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_ALL;
            desc.mAlphaToCoverage = false;
            desc.mIndependentBlend = false;
            self.blend_states.put(id, desc) catch unreachable;
        }

        {
            const id = IdLocal.init("bs_premultiplied");
            var desc = std.mem.zeroes(graphics.BlendStateDesc);
            desc.mSrcFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_ALL;
            desc.mAlphaToCoverage = false;
            desc.mIndependentBlend = false;
            self.blend_states.put(id, desc) catch unreachable;
        }

        {
            // TODO(gmodarelli): Find out what type of blending this is :)
            const id = IdLocal.init("bs_atmosphere");
            var desc = std.mem.zeroes(graphics.BlendStateDesc);
            desc.mSrcFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_ALL;
            desc.mAlphaToCoverage = false;
            desc.mIndependentBlend = false;
            self.blend_states.put(id, desc) catch unreachable;
        }

        {
            const id = IdLocal.init("bs_additive");
            var desc = std.mem.zeroes(graphics.BlendStateDesc);
            desc.mSrcFactors[0] = graphics.BlendConstant.BC_SRC_ALPHA;
            desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ONE;
            desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_ALL;
            desc.mAlphaToCoverage = false;
            desc.mIndependentBlend = false;
            self.blend_states.put(id, desc) catch unreachable;
        }

        {
            const id = IdLocal.init("bs_multiply");
            var desc = std.mem.zeroes(graphics.BlendStateDesc);
            desc.mSrcFactors[0] = graphics.BlendConstant.BC_DST_COLOR;
            desc.mDstFactors[0] = graphics.BlendConstant.BC_ZERO;
            desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_DST_ALPHA;
            desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_ALL;
            desc.mAlphaToCoverage = false;
            desc.mIndependentBlend = false;
            self.blend_states.put(id, desc) catch unreachable;
        }

        {
            // TODO(gmodarelli): Find out what type of blending this is :)
            const id = IdLocal.init("bs_im3d");
            var desc = std.mem.zeroes(graphics.BlendStateDesc);
            desc.mBlendModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcFactors[0] = graphics.BlendConstant.BC_SRC_ALPHA;
            desc.mDstFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mBlendAlphaModes[0] = graphics.BlendMode.BM_ADD;
            desc.mSrcAlphaFactors[0] = graphics.BlendConstant.BC_ONE_MINUS_SRC_ALPHA;
            desc.mDstAlphaFactors[0] = graphics.BlendConstant.BC_ZERO;
            desc.mColorWriteMasks[0] = graphics.ColorMask.COLOR_MASK_ALL;
            desc.mRenderTargetMask = graphics.BlendStateTargets.BLEND_STATE_TARGET_0;
            desc.mIndependentBlend = false;
            self.blend_states.put(id, desc) catch unreachable;
        }
    }

    pub fn getPsoBinsCount(self: *PSOManager) usize {
        return self.pso_bins.items.len;
    }

    pub fn getPsoBinId(self: *PSOManager, id: IdLocal) ?u32 {
        for (self.pso_bins.items, 0..) |pso_bin, pso_bin_id| {
            if (id.hash == pso_bin.gbuffer_id.hash or id.hash == pso_bin.shadow_caster_id.hash) {
                return @intCast(pso_bin_id);
            }
        }

        return null;
    }

    pub fn getPipeline(self: *PSOManager, id: IdLocal) [*c]graphics.Pipeline {
        const handle = self.pso_map.get(id).?;
        const pso = self.pso_pool.getColumn(handle, .pipeline) catch unreachable;
        return pso;
    }

    pub fn getRootSignature(self: *PSOManager, id: IdLocal) [*c]graphics.RootSignature {
        const handle = self.pso_map.get(id).?;
        const root_signature = self.pso_pool.getColumn(handle, .root_signature) catch unreachable;
        return root_signature;
    }

    pub fn createPipelines(self: *PSOManager) void {
        self.pso_bins.clearRetainingCapacity();

        var rasterizer_cull_back = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_cull_back.mCullMode = graphics.CullMode.CULL_MODE_BACK;

        var rasterizer_wireframe = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_wireframe.mCullMode = graphics.CullMode.CULL_MODE_NONE;
        rasterizer_wireframe.mFillMode = graphics.FillMode.FILL_MODE_WIREFRAME;

        var rasterizer_cull_none = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_cull_none.mCullMode = graphics.CullMode.CULL_MODE_NONE;

        var rasterizer_imgui = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_imgui.mCullMode = graphics.CullMode.CULL_MODE_NONE;
        rasterizer_imgui.mFrontFace = graphics.FrontFace.FRONT_FACE_CW;
        rasterizer_imgui.mDepthClampEnable = true;

        // Atmosphere Scattering
        {
            // Procedural Sky
            {
                var null_samplers = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("procedural_sky"), "procedural_sky.comp", &null_samplers);
                self.createComputePipeline(IdLocal.init("bake_sky_to_sh"), "bake_sky_to_sh.comp", &null_samplers);
                self.createComputePipeline(IdLocal.init("bake_skyface_to_sh"), "bake_skyface_to_sh.comp", &null_samplers);
            }

            // Draw Sky
            {
                var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };
                const render_targets = [_]graphics.TinyImageFormat{self.renderer.scene_color.*.mFormat};

                const depth_state = getDepthStateDesc(false, true, graphics.CompareMode.CMP_GREATER);

                const desc = GraphicsPipelineDesc{
                    .id = IdLocal.init("draw_sky"),
                    .vert_shader_name = "draw_sky.vert",
                    .frag_shader_name = "draw_sky.frag",
                    .render_targets = @constCast(&render_targets),
                    .rasterizer_state = rasterizer_cull_none,
                    .sampler_ids = &sampler_ids,
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .vertex_layout_id = IdLocal.init("pos_uv0_col"),
                };
                self.createGraphicsPipeline(desc);
            }
        }

        // Terrain
        // ======
        {
            // GBuffer
            {
                var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };
                const render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.gbuffer_0.*.mFormat,
                    self.renderer.gbuffer_1.*.mFormat,
                    self.renderer.gbuffer_2.*.mFormat,
                };

                const depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);

                const desc = GraphicsPipelineDesc{
                    .id = IdLocal.init("terrain_gbuffer"),
                    .vert_shader_name = "terrain_gbuffer.vert",
                    .frag_shader_name = "terrain_gbuffer.frag",
                    .render_targets = @constCast(&render_targets),
                    .rasterizer_state = rasterizer_cull_back,
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .vertex_layout_id = IdLocal.init("pos_uv0_col"),
                    .sampler_ids = &sampler_ids,
                };
                self.createGraphicsPipeline(desc);
            }

            // Shadows Caster
            {
                var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };
                const render_targets = [_]graphics.TinyImageFormat{};
                const depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GREATER);
                var rasterizer = rasterizer_cull_none;
                rasterizer.mDepthBias = -1.0;
                rasterizer.mSlopeScaledDepthBias = -4.0;

                const desc = GraphicsPipelineDesc{
                    .id = IdLocal.init("terrain_shadow_caster"),
                    .vert_shader_name = "terrain_shadow_caster.vert",
                    .frag_shader_name = "terrain_shadow_caster.frag",
                    .render_targets = @constCast(&render_targets),
                    .rasterizer_state = rasterizer,
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .vertex_layout_id = IdLocal.init("pos_uv0_col"),
                    .sampler_ids = &sampler_ids,
                };
                self.createGraphicsPipeline(desc);
            }
        }

        // Lit
        // ===
        {
            // GBuffer
            {
                var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };
                const render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.gbuffer_0.*.mFormat,
                    self.renderer.gbuffer_1.*.mFormat,
                    self.renderer.gbuffer_2.*.mFormat,
                };

                const depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);

                var desc = GraphicsPipelineDesc{
                    .id = IdLocal.init("lit_gbuffer_opaque"),
                    .vert_shader_name = "lit_gbuffer.vert",
                    .frag_shader_name = "lit_gbuffer_opaque.frag",
                    .render_targets = @constCast(&render_targets),
                    .rasterizer_state = rasterizer_cull_back,
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .vertex_layout_id = IdLocal.init("pos_uv0_nor_tan_col"),
                    .sampler_ids = &sampler_ids,
                };
                self.createGraphicsPipeline(desc);

                desc.id = IdLocal.init("lit_gbuffer_cutout");
                desc.frag_shader_name = "lit_gbuffer_cutout.frag";
                desc.rasterizer_state = rasterizer_cull_none;
                self.createGraphicsPipeline(desc);
            }

            // Shadows Caster
            {
                var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };
                const render_targets = [_]graphics.TinyImageFormat{};
                const depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GREATER);
                var rasterizer = rasterizer_cull_back;
                rasterizer.mDepthBias = -1.0;
                rasterizer.mSlopeScaledDepthBias = -4.0;

                var desc = GraphicsPipelineDesc{
                    .id = IdLocal.init("lit_shadow_caster_opaque"),
                    .vert_shader_name = "lit_shadow_caster.vert",
                    .frag_shader_name = "lit_shadow_caster_opaque.frag",
                    .render_targets = @constCast(&render_targets),
                    .rasterizer_state = rasterizer,
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .vertex_layout_id = IdLocal.init("pos_uv0_nor_tan_col"),
                    .sampler_ids = &sampler_ids,
                };
                self.createGraphicsPipeline(desc);

                rasterizer = rasterizer_cull_none;
                rasterizer.mDepthBias = -1.0;
                rasterizer.mSlopeScaledDepthBias = -4.0;
                desc.id = IdLocal.init("lit_shadow_caster_cutout");
                desc.frag_shader_name = "lit_shadow_caster_cutout.frag";
                desc.rasterizer_state = rasterizer;
                self.createGraphicsPipeline(desc);
            }
        }

        // GPU Debug Line Rendering PSOs
        // =============================
        {
            // Clear counters
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("debug_line_rendering_clear"), "debug_line_rendering_clear.comp", &sampler_ids);
            }

            {
                var sampler_ids = [_]IdLocal{};
                var render_targets = [_]graphics.TinyImageFormat{self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat};

                const depth_state = getDepthStateDesc(false, true, graphics.CompareMode.CMP_GEQUAL);
                const desc = GraphicsPipelineDesc{
                    .id = IdLocal.init("debug_line_rendering_draw"),
                    .topology = graphics.PrimitiveTopology.PRIMITIVE_TOPO_LINE_LIST,
                    .vert_shader_name = "debug_line_rendering.vert",
                    .frag_shader_name = "debug_line_rendering.frag",
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .render_targets = @constCast(&render_targets),
                    .rasterizer_state = rasterizer_cull_none,
                    .blend_state = self.blend_states.get(IdLocal.init("bs_im3d")).?,
                    .vertex_layout_id = IdLocal.init("debug_line"),
                    .sampler_ids = &sampler_ids,
                };
                self.createGraphicsPipeline(desc);
            }
        }

        // GPU-Driven Rendering PSOs
        // =========================
        {

            // Culling: Clear UAV
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_clear_counters"), "meshlet_clear_counters.comp", &sampler_ids);
            }

            // Culling: Cull Instances
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_cull_instances"), "meshlet_cull_instances.comp", &sampler_ids);
            }

            // Culling: Build Meshlets Cull Args
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_build_meshlets_cull_args"), "meshlet_build_cull_meshlets_args.comp", &sampler_ids);
            }

            // Culling: Cull Meshlets
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_cull_meshlets"), "meshlet_cull_meshlets.comp", &sampler_ids);
            }

            // Binning: Prepare Args
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_binning_prepare_args"), "meshlet_binning_prepare_args.comp", &sampler_ids);
            }

            // Binning: Classify Meshlets
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_binning_classify_meshlets"), "meshlet_binning_classify_meshlets.comp", &sampler_ids);
            }

            // Binning: Allocate Bin Ranges
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_binning_allocate_bin_ranges"), "meshlet_binning_allocate_bin.comp", &sampler_ids);
            }

            // Binning: Write Bin Ranges
            {
                var sampler_ids = [_]IdLocal{};
                self.createComputePipeline(IdLocal.init("meshlet_binning_write_bin_ranges"), "meshlet_binning_write_bins.comp", &sampler_ids);
            }

            // Meshlets Rasterization
            {
                const gbuffer_opaque_id = IdLocal.init("meshlet_gbuffer_opaque");
                const gbuffer_masked_id = IdLocal.init("meshlet_gbuffer_masked");
                const depth_only_opaque_id = IdLocal.init("meshlet_depth_only_opaque");
                const depth_only_masked_id = IdLocal.init("meshlet_depth_only_masked");

                var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };

                const gbuffer_render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.gbuffer_0.*.mFormat,
                    self.renderer.gbuffer_1.*.mFormat,
                    self.renderer.gbuffer_2.*.mFormat,
                };

                const depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);

                var desc = MeshPipelineDesc{
                    .id = gbuffer_opaque_id,
                    .mesh_shader_name = "meshlet_rasterizer.mesh",
                    .frag_shader_name = "meshlet_rasterizer_opaque.frag",
                    .render_targets = @constCast(&gbuffer_render_targets),
                    .rasterizer_state = rasterizer_cull_back,
                    .depth_state = depth_state,
                    .depth_format = self.renderer.depth_buffer.*.mFormat,
                    .sampler_ids = &sampler_ids,
                };
                self.createMeshPipeline(desc);

                desc.id = gbuffer_masked_id;
                desc.rasterizer_state = rasterizer_cull_none;
                desc.frag_shader_name = "meshlet_rasterizer_masked.frag";
                self.createMeshPipeline(desc);

                var rasterizer_shadow = std.mem.zeroes(graphics.RasterizerStateDesc);
                rasterizer_shadow.mCullMode = graphics.CullMode.CULL_MODE_NONE;
                rasterizer_shadow.mDepthBias = -50.0;
                rasterizer_shadow.mSlopeScaledDepthBias = -20.0;

                desc.id = depth_only_opaque_id;
                desc.rasterizer_state = rasterizer_shadow;
                desc.frag_shader_name = null;
                desc.depth_format = self.renderer.shadow_depth_buffers[0].*.mFormat;
                self.createMeshPipeline(desc);

                desc.id = depth_only_masked_id;
                desc.rasterizer_state = rasterizer_shadow;
                desc.frag_shader_name = "meshlet_rasterizer_masked_depth_only.frag";
                self.createMeshPipeline(desc);

                self.pso_bins.append(.{ .gbuffer_id = gbuffer_opaque_id, .shadow_caster_id = depth_only_opaque_id }) catch unreachable;
                self.pso_bins.append(.{ .gbuffer_id = gbuffer_masked_id, .shadow_caster_id = depth_only_masked_id }) catch unreachable;
            }
        }

        // Deferred
        {
            var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge, StaticSamplers.point_clamp_edge, StaticSamplers.linear_clamp_cmp_greater };
            const render_targets = [_]graphics.TinyImageFormat{self.renderer.scene_color.*.mFormat};

            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("deferred"),
                .vert_shader_name = "fullscreen.vert",
                .frag_shader_name = "deferred_shading.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_none,
                .sampler_ids = &sampler_ids,
            };
            self.createGraphicsPipeline(desc);
        }

        // ImGUI Pipeline
        {
            var sampler_ids = [_]IdLocal{StaticSamplers.linear_repeat};
            var render_targets = [_]graphics.TinyImageFormat{self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat};
            const depth_state = getDepthStateDesc(true, false, graphics.CompareMode.CMP_ALWAYS);

            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("imgui"),
                .vert_shader_name = "imgui.vert",
                .frag_shader_name = "imgui.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_imgui,
                .blend_state = self.blend_states.get(IdLocal.init("bs_transparent")).?,
                .depth_state = depth_state,
                .vertex_layout_id = IdLocal.init("imgui"),
                .sampler_ids = &sampler_ids,
            };
            self.createGraphicsPipeline(desc);
        }

        // Im3d Pipelines
        {
            var sampler_ids = [_]IdLocal{};
            var render_targets = [_]graphics.TinyImageFormat{self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat};

            // Points
            var desc = GraphicsPipelineDesc{
                .id = IdLocal.init("im3d_points"),
                .topology = graphics.PrimitiveTopology.PRIMITIVE_TOPO_POINT_LIST,
                .vert_shader_name = "im3d_points_lines.vert",
                .geom_shader_name = "im3d_points.geom",
                .frag_shader_name = "im3d_points.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_none,
                .blend_state = self.blend_states.get(IdLocal.init("bs_im3d")).?,
                .vertex_layout_id = IdLocal.init("im3d"),
                .sampler_ids = &sampler_ids,
            };
            self.createGraphicsPipeline(desc);
            // Lines
            desc.id = IdLocal.init("im3d_lines");
            desc.topology = graphics.PrimitiveTopology.PRIMITIVE_TOPO_LINE_LIST;
            desc.geom_shader_name = "im3d_lines.geom";
            desc.frag_shader_name = "im3d_lines.frag";
            self.createGraphicsPipeline(desc);
            // Triangles
            desc.id = IdLocal.init("im3d_triangles");
            desc.topology = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            desc.vert_shader_name = "im3d_triangles.vert";
            desc.geom_shader_name = null;
            desc.frag_shader_name = "im3d_triangles.frag";
            self.createGraphicsPipeline(desc);
        }

        // Copy Scene Color and Depth
        {
            var sampler_ids = [_]IdLocal{StaticSamplers.linear_clamp_edge};
            const render_targets = [_]graphics.TinyImageFormat{
                self.renderer.scene_color_copy.*.mFormat,
                self.renderer.depth_buffer_copy.*.mFormat,
            };

            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("copy_scene_color_and_depth"),
                .vert_shader_name = "fullscreen.vert",
                .frag_shader_name = "copy_scene_color_and_depth.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_none,
                .sampler_ids = &sampler_ids,
            };
            self.createGraphicsPipeline(desc);
        }

        // Water
        {
            var sampler_ids = [_]IdLocal{ StaticSamplers.linear_repeat, StaticSamplers.linear_clamp_edge };
            const render_targets = [_]graphics.TinyImageFormat{
                self.renderer.scene_color.*.mFormat,
            };

            const depth_state = getDepthStateDesc(false, true, graphics.CompareMode.CMP_GEQUAL);

            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("water"),
                .vert_shader_name = "water.vert",
                .frag_shader_name = "water.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_back,
                .depth_state = depth_state,
                .depth_format = self.renderer.depth_buffer.*.mFormat,
                .vertex_layout_id = IdLocal.init("pos_uv0_nor_tan_col"),
                .sampler_ids = &sampler_ids,
            };
            self.createGraphicsPipeline(desc);
        }

        // Post Processing
        {
            // Bloom
            {
                {
                    var sampler_ids = [_]IdLocal{StaticSamplers.linear_clamp_edge};
                    self.createComputePipeline(IdLocal.init("bloom_extract"), "bloom_extract_downsample_hdr.comp", &sampler_ids);
                    self.createComputePipeline(IdLocal.init("downsample_bloom_all"), "downsample_bloom_all.comp", &sampler_ids);
                    self.createComputePipeline(IdLocal.init("tonemap"), "tonemapping.comp", &sampler_ids);
                    self.createComputePipeline(IdLocal.init("vignette"), "vignette.comp", &sampler_ids);
                }

                {
                    var sampler_ids = [_]IdLocal{StaticSamplers.linear_clamp_border};
                    self.createComputePipeline(IdLocal.init("upsample_and_blur"), "upsample_blur.comp", &sampler_ids);
                }

                {
                    var sampler_ids = [_]IdLocal{};
                    self.createComputePipeline(IdLocal.init("blur_gaussian"), "blur_gaussian.comp", &sampler_ids);
                }
            }
        }

        // Compute utilities
        {
            var sampler_ids = [_]IdLocal{};
            self.createComputePipeline(IdLocal.init("clear_uav"), "clear_uav.comp", &sampler_ids);
        }

        // UI
        {
            var sampler_ids = [_]IdLocal{StaticSamplers.linear_repeat};
            var render_targets = [_]graphics.TinyImageFormat{self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat};
            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("ui"),
                .vert_shader_name = "ui.vert",
                .frag_shader_name = "ui.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_none,
                .blend_state = self.blend_states.get(IdLocal.init("bs_premultiplied")).?,
                .sampler_ids = &sampler_ids,
            };
            self.createGraphicsPipeline(desc);
        }

        // IBL Pipelines
        {
            var sampler_ids = [_]IdLocal{StaticSamplers.skybox};
            self.createComputePipeline(IdLocal.init("brdf_integration"), "brdf_integration.comp", &sampler_ids);
            self.createComputePipeline(IdLocal.init("compute_irradiance_map"), "compute_irradiance_map.comp", &sampler_ids);
            self.createComputePipeline(IdLocal.init("compute_specular_map"), "compute_specular_map.comp", &sampler_ids);
        }

        // Tonemapper
        {
            var sampler_ids = [_]IdLocal{StaticSamplers.linear_clamp_edge};
            var render_targets = [_]graphics.TinyImageFormat{self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat};
            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("tonemapper"),
                .vert_shader_name = "fullscreen.vert",
                .frag_shader_name = "tonemapper.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_none,
                .sampler_ids = &sampler_ids,
                .blend_state = self.blend_states.get(IdLocal.init("bs_premultiplied")).?,
            };
            self.createGraphicsPipeline(desc);
        }

        // Buffer Visualizer
        {
            var sampler_ids = [_]IdLocal{StaticSamplers.linear_clamp_edge};
            var render_targets = [_]graphics.TinyImageFormat{self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat};
            const desc = GraphicsPipelineDesc{
                .id = IdLocal.init("buffer_visualizer"),
                .vert_shader_name = "fullscreen.vert",
                .frag_shader_name = "buffer_visualizer.frag",
                .render_targets = @constCast(&render_targets),
                .rasterizer_state = rasterizer_cull_none,
                .sampler_ids = &sampler_ids,
                .blend_state = self.blend_states.get(IdLocal.init("bs_premultiplied")).?,
            };
            self.createGraphicsPipeline(desc);
        }
    }

    pub fn destroyPipelines(self: *PSOManager) void {
        var pipeline_handles = self.pso_pool.liveHandles();
        while (pipeline_handles.next()) |handle| {
            const shader = self.pso_pool.getColumn(handle, .shader) catch unreachable;
            const root_signature = self.pso_pool.getColumn(handle, .root_signature) catch unreachable;
            const pipeline = self.pso_pool.getColumn(handle, .pipeline) catch unreachable;
            graphics.removePipeline(self.renderer.renderer, pipeline);
            graphics.removeRootSignature(self.renderer.renderer, root_signature);
            graphics.removeShader(self.renderer.renderer, shader);
        }
        self.pso_pool.clear();
        self.pso_map.clearRetainingCapacity();
    }

    fn createGraphicsPipeline(self: *PSOManager, desc: GraphicsPipelineDesc) void {
        var shader: [*c]graphics.Shader = null;
        var root_signature: [*c]graphics.RootSignature = null;
        var pipeline: [*c]graphics.Pipeline = null;

        var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
        shader_load_desc.mVert.pFileName = @ptrCast(desc.vert_shader_name);
        if (desc.frag_shader_name) |shader_name| {
            shader_load_desc.mFrag.pFileName = @ptrCast(shader_name);
        }
        if (desc.geom_shader_name) |shader_name| {
            shader_load_desc.mGeom.pFileName = @ptrCast(shader_name);
        }
        resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

        var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
        root_signature_desc.mShaderCount = 1;
        root_signature_desc.ppShaders = @ptrCast(&shader);

        if (desc.sampler_ids.len > 0) {
            var static_sampler_names = std.mem.zeroes([8][*c]const u8);
            var static_samplers = std.mem.zeroes([8][*c]graphics.Sampler);

            for (0..desc.sampler_ids.len) |i| {
                const sampler = self.samplers.getSampler(desc.sampler_ids[i]);
                static_sampler_names[i] = @ptrCast(sampler.name);
                static_samplers[i] = sampler.sampler;
            }

            root_signature_desc.mStaticSamplerCount = @intCast(desc.sampler_ids.len);
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
        }

        graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

        var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
        pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
        pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
        pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = desc.topology;
        pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = @intCast(desc.render_targets.len);
        pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(desc.render_targets.ptr);

        if (desc.depth_state) |state| {
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = @constCast(&state);
            if (desc.depth_format) |format| {
                pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = format;
            }
        }

        pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
        pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;

        pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
        pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;

        if (desc.vertex_layout_id) |layout_id| {
            const vertex_layout = self.renderer.vertex_layouts_map.get(layout_id).?;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&vertex_layout);
        }

        if (desc.rasterizer_state) |state| {
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = @constCast(&state);
        }

        if (desc.blend_state) |state| {
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = @constCast(&state);
        }

        graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

        const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
        self.pso_map.put(desc.id, handle) catch unreachable;
    }

    fn createComputePipeline(self: *PSOManager, id: IdLocal, shader_name: []const u8, sampler_ids: []IdLocal) void {
        var shader: [*c]graphics.Shader = null;
        var root_signature: [*c]graphics.RootSignature = null;
        var pipeline: [*c]graphics.Pipeline = null;

        var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
        shader_load_desc.mComp.pFileName = @ptrCast(shader_name);
        resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

        var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
        root_signature_desc.mShaderCount = 1;
        root_signature_desc.ppShaders = @ptrCast(&shader);

        if (sampler_ids.len > 0) {
            var static_sampler_names = std.mem.zeroes([8][*c]const u8);
            var static_samplers = std.mem.zeroes([8][*c]graphics.Sampler);

            for (0..sampler_ids.len) |i| {
                const sampler = self.samplers.getSampler(sampler_ids[i]);
                static_sampler_names[i] = @ptrCast(sampler.name);
                static_samplers[i] = sampler.sampler;
            }

            root_signature_desc.mStaticSamplerCount = @intCast(sampler_ids.len);
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
        }

        graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

        var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
        pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
        pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
        pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
        graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

        const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
        self.pso_map.put(id, handle) catch unreachable;
    }

    fn createMeshPipeline(self: *PSOManager, desc: MeshPipelineDesc) void {
        var shader: [*c]graphics.Shader = null;
        var root_signature: [*c]graphics.RootSignature = null;
        var pipeline: [*c]graphics.Pipeline = null;

        var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
        shader_load_desc.mMesh.pFileName = @ptrCast(desc.mesh_shader_name);
        if (desc.ampl_shader_name) |shader_name| {
            shader_load_desc.mAmplification.pFileName = @ptrCast(shader_name);
        }
        if (desc.frag_shader_name) |shader_name| {
            shader_load_desc.mFrag.pFileName = @ptrCast(shader_name);
        }
        resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

        var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
        root_signature_desc.mShaderCount = 1;
        root_signature_desc.ppShaders = @ptrCast(&shader);

        if (desc.sampler_ids.len > 0) {
            var static_sampler_names = std.mem.zeroes([8][*c]const u8);
            var static_samplers = std.mem.zeroes([8][*c]graphics.Sampler);

            for (0..desc.sampler_ids.len) |i| {
                const sampler = self.samplers.getSampler(desc.sampler_ids[i]);
                static_sampler_names[i] = @ptrCast(sampler.name);
                static_samplers[i] = sampler.sampler;
            }

            root_signature_desc.mStaticSamplerCount = @intCast(desc.sampler_ids.len);
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
        }

        graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

        var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
        pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_MESH;
        pipeline_desc.__union_field1.mMeshDesc = std.mem.zeroes(graphics.MeshPipelineDesc);
        pipeline_desc.__union_field1.mMeshDesc.mRenderTargetCount = @intCast(desc.render_targets.len);
        pipeline_desc.__union_field1.mMeshDesc.pColorFormats = @ptrCast(desc.render_targets.ptr);

        if (desc.depth_state) |state| {
            pipeline_desc.__union_field1.mMeshDesc.pDepthState = @constCast(&state);
            if (desc.depth_format) |format| {
                pipeline_desc.__union_field1.mMeshDesc.mDepthStencilFormat = format;
            }
        }

        pipeline_desc.__union_field1.mMeshDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
        pipeline_desc.__union_field1.mMeshDesc.mSampleQuality = 0;

        pipeline_desc.__union_field1.mMeshDesc.pRootSignature = root_signature;
        pipeline_desc.__union_field1.mMeshDesc.pShaderProgram = shader;

        if (desc.rasterizer_state) |state| {
            pipeline_desc.__union_field1.mMeshDesc.pRasterizerState = @constCast(&state);
        }

        if (desc.blend_state) |state| {
            pipeline_desc.__union_field1.mMeshDesc.pBlendState = @constCast(&state);
        }

        graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

        const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
        self.pso_map.put(desc.id, handle) catch unreachable;
    }

    fn getDepthStateDesc(depth_write: bool, depth_test: bool, depth_func: graphics.CompareMode) graphics.DepthStateDesc {
        var desc = std.mem.zeroes(graphics.DepthStateDesc);
        desc.mDepthWrite = depth_write;
        desc.mDepthTest = depth_test;
        desc.mDepthFunc = depth_func;

        return desc;
    }
};

const StaticSamplers = struct {
    pub const StaticSampler = struct {
        sampler: [*c]graphics.Sampler,
        name: []const u8,
    };

    const SamplersMap = std.AutoHashMap(IdLocal, StaticSampler);

    pub const linear_repeat = IdLocal.init("linear_repeat");
    pub const linear_clamp_edge = IdLocal.init("linear_clamp_edge");
    pub const linear_clamp_cmp_greater = IdLocal.init("linear_clamp_cmp_greater");
    pub const linear_clamp_border = IdLocal.init("linear_clamp_border");
    pub const point_repeat = IdLocal.init("point_repeat");
    pub const point_clamp_edge = IdLocal.init("point_clamp_edge");
    pub const point_clamp_border = IdLocal.init("point_clamp_border");
    pub const skybox = IdLocal.init("skybox");

    samplers_map: SamplersMap = undefined,

    pub fn create(renderer: [*c]graphics.Renderer, allocator: std.mem.Allocator) StaticSamplers {
        var static_samplers = StaticSamplers{};
        static_samplers.samplers_map = SamplersMap.init(allocator);

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(linear_repeat, .{ .sampler = sampler, .name = "g_linear_repeat_sampler" }) catch unreachable;
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = .ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = .ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = .ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = .FILTER_LINEAR;
            desc.mMagFilter = .FILTER_LINEAR;
            desc.mMipMapMode = .MIPMAP_MODE_NEAREST;
            desc.mCompareFunc = .CMP_GREATER;
            desc.mSetLodRange = true;
            desc.mMinLod = 0.0;
            desc.mMaxLod = std.math.floatMax(f32);

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(linear_clamp_cmp_greater, .{ .sampler = sampler, .name = "g_linear_clamp_cmp_greater_sampler" }) catch unreachable;
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(linear_clamp_edge, .{ .sampler = sampler, .name = "g_linear_clamp_edge_sampler" }) catch unreachable;
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mMinFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMagFilter = graphics.FilterType.FILTER_LINEAR;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_LINEAR;

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(linear_clamp_border, .{ .sampler = sampler, .name = "g_linear_clamp_border_sampler" }) catch unreachable;
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_REPEAT;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(point_repeat, .{ .sampler = sampler, .name = "g_point_repeat_sampler" }) catch unreachable;
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_EDGE;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(point_clamp_edge, .{ .sampler = sampler, .name = "g_point_clamp_edge_sampler" }) catch unreachable;
        }

        {
            var desc = std.mem.zeroes(graphics.SamplerDesc);
            desc.mAddressU = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressV = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mAddressW = graphics.AddressMode.ADDRESS_MODE_CLAMP_TO_BORDER;
            desc.mMinFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMagFilter = graphics.FilterType.FILTER_NEAREST;
            desc.mMipMapMode = graphics.MipMapMode.MIPMAP_MODE_NEAREST;

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(point_clamp_border, .{ .sampler = sampler, .name = "g_point_clamp_border_sampler" }) catch unreachable;
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

            var sampler: [*c]graphics.Sampler = null;
            graphics.addSampler(renderer, &desc, false, &sampler);
            static_samplers.samplers_map.put(skybox, .{ .sampler = sampler, .name = "g_skybox_sampler" }) catch unreachable;
        }

        return static_samplers;
    }

    pub fn getSampler(self: *StaticSamplers, id: IdLocal) StaticSampler {
        return self.samplers_map.get(id).?;
    }

    pub fn exit(self: *StaticSamplers, renderer: [*c]graphics.Renderer) void {
        graphics.removeSampler(renderer, self.samplers_map.get(linear_repeat).?.sampler);
        graphics.removeSampler(renderer, self.samplers_map.get(linear_clamp_edge).?.sampler);
        graphics.removeSampler(renderer, self.samplers_map.get(linear_clamp_border).?.sampler);
        graphics.removeSampler(renderer, self.samplers_map.get(point_repeat).?.sampler);
        graphics.removeSampler(renderer, self.samplers_map.get(point_clamp_edge).?.sampler);
        graphics.removeSampler(renderer, self.samplers_map.get(point_clamp_border).?.sampler);
        graphics.removeSampler(renderer, self.samplers_map.get(skybox).?.sampler);

        self.samplers_map.deinit();
    }
};
