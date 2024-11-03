const std = @import("std");

const IdLocal = @import("../core/core.zig").IdLocal;
const Renderer = @import("renderer.zig").Renderer;
const zforge = @import("zforge");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const atmosphere_render_pass = @import("../systems/renderer_system/atmosphere_render_pass.zig");

const Pool = @import("zpool").Pool;

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

const PSOPool = Pool(16, 16, graphics.Shader, struct { shader: [*c]graphics.Shader, root_signature: [*c]graphics.RootSignature, pipeline: [*c]graphics.Pipeline });
const PSOHandle = PSOPool.Handle;
const PSOMap = std.AutoHashMap(IdLocal, PSOHandle);

pub const PSOManager = struct {
    allocator: std.mem.Allocator = undefined,
    renderer: *Renderer = undefined,

    pso_pool: PSOPool = undefined,
    pso_map: PSOMap = undefined,
    samplers: StaticSamplers = undefined,

    pub fn init(self: *PSOManager, renderer: *Renderer, allocator: std.mem.Allocator) !void {
        std.debug.assert(renderer.renderer != null);

        self.allocator = allocator;
        self.renderer = renderer;
        self.pso_pool = PSOPool.initMaxCapacity(allocator) catch unreachable;
        self.pso_map = PSOMap.init(allocator);
        self.samplers = StaticSamplers.create(renderer.renderer, allocator);
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
        // self.depth_states_map.deinit();

        self.samplers.exit(self.renderer.renderer);
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
        var rasterizer_cull_back = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_cull_back.mCullMode = graphics.CullMode.CULL_MODE_BACK;

        var rasterizer_wireframe = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_wireframe.mCullMode = graphics.CullMode.CULL_MODE_NONE;
        rasterizer_wireframe.mFillMode = graphics.FillMode.FILL_MODE_WIREFRAME;

        var rasterizer_cull_none = std.mem.zeroes(graphics.RasterizerStateDesc);
        rasterizer_cull_none.mCullMode = graphics.CullMode.CULL_MODE_NONE;

        const pos_uv0_nor_tan_col_vertex_layout = self.renderer.vertex_layouts_map.get(IdLocal.init("pos_uv0_nor_tan_col")).?;
        const pos_uv0_nor_tan_col_uv1_vertex_layout = self.renderer.vertex_layouts_map.get(IdLocal.init("pos_uv0_nor_tan_col_uv1")).?;
        const pos_uv0_col_vertex_layout = self.renderer.vertex_layouts_map.get(IdLocal.init("pos_uv0_col")).?;
        const im3d_vertex_layout = self.renderer.vertex_layouts_map.get(IdLocal.init("im3d")).?;
        const imgui_vertex_layout = self.renderer.vertex_layouts_map.get(IdLocal.init("imgui")).?;

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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                var static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{atmosphere_render_pass.transmittance_lut_format};

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                var static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
                pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                var static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{self.renderer.scene_color.*.mFormat};

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
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{self.renderer.scene_color.*.mFormat};

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
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));


            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.gbuffer_0.*.mFormat,
                self.renderer.gbuffer_1.*.mFormat,
                self.renderer.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.gbuffer_0.*.mFormat,
                self.renderer.gbuffer_1.*.mFormat,
                self.renderer.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.gbuffer_0.*.mFormat,
                self.renderer.gbuffer_1.*.mFormat,
                self.renderer.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = 0;

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.gbuffer_0.*.mFormat,
                self.renderer.gbuffer_1.*.mFormat,
                self.renderer.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_back;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.gbuffer_0.*.mFormat,
                self.renderer.gbuffer_1.*.mFormat,
                self.renderer.gbuffer_2.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);

            var depth_state = getDepthStateDesc(true, true, graphics.CompareMode.CMP_GEQUAL);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = self.renderer.depth_buffer.*.mFormat;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&pos_uv0_nor_tan_col_uv1_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
            const point_clamp_edge = self.samplers.getSampler(StaticSamplers.point_clamp_edge);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name), @ptrCast(linear_clamp_edge.name), @ptrCast(point_clamp_edge.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler, linear_clamp_edge.sampler, point_clamp_edge.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.scene_color.*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

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

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat,
            };

            var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
            pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
            pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
            pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
            pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
            pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);

            var depth_state = getDepthStateDesc(true, false, graphics.CompareMode.CMP_ALWAYS);
            pipeline_desc.__union_field1.mGraphicsDesc.pDepthState = &depth_state;
            pipeline_desc.__union_field1.mGraphicsDesc.mDepthStencilFormat = graphics.TinyImageFormat.UNDEFINED;

            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&imgui_vertex_layout);
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_POINT_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&im3d_vertex_layout);
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_LINE_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&im3d_vertex_layout);
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = @constCast(&im3d_vertex_layout);
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_state_desc;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }
        }

        // Post Processing
        {
            // Bloom Extract
            {
                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                const static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                self.createComputePipeline(IdLocal.init("bloom_extract"), "bloom_extract_and_downsample.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
            }

            // Downsample Bloom All
            {
                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                const static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                self.createComputePipeline(IdLocal.init("downsample_bloom_all"), "downsample_bloom_all.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
            }

            // Blur
            {
                const static_sampler_names = [_][*c]const u8{};
                const static_samplers = [_][*c]graphics.Sampler{};
                self.createComputePipeline(IdLocal.init("blur"), "blur.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
            }

            // Upsample and Blur
            {
                const linear_clamp_border = self.samplers.getSampler(StaticSamplers.linear_clamp_border);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_border.name) };
                const static_samplers = [_][*c]graphics.Sampler{ linear_clamp_border.sampler };

                self.createComputePipeline(IdLocal.init("upsample_and_blur"), "upsample_and_blur.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
            }

            // Upsample and Blur
            {
                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                const static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                self.createComputePipeline(IdLocal.init("apply_bloom"), "apply_bloom.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
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
                resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

                const linear_clamp_edge = self.samplers.getSampler(StaticSamplers.linear_clamp_edge);
                const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_clamp_edge.name) };
                var static_samplers = [_][*c]graphics.Sampler{ linear_clamp_edge.sampler };

                var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
                root_signature_desc.mStaticSamplerCount = static_samplers.len;
                root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
                root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
                root_signature_desc.mShaderCount = 1;
                root_signature_desc.ppShaders = @ptrCast(&shader);
                graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

                var render_targets = [_]graphics.TinyImageFormat{
                    self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat,
                };

                var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
                pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_GRAPHICS;
                pipeline_desc.__union_field1.mGraphicsDesc = std.mem.zeroes(graphics.GraphicsPipelineDesc);
                pipeline_desc.__union_field1.mGraphicsDesc.mPrimitiveTopo = graphics.PrimitiveTopology.PRIMITIVE_TOPO_TRI_LIST;
                pipeline_desc.__union_field1.mGraphicsDesc.mRenderTargetCount = render_targets.len;
                pipeline_desc.__union_field1.mGraphicsDesc.pColorFormats = @ptrCast(&render_targets);
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
                pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
                pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
                pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
                pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
                pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
                pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = null;
                graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

                const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
                self.pso_map.put(id, handle) catch unreachable;
            }
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
            resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

            const linear_repeat = self.samplers.getSampler(StaticSamplers.linear_repeat);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(linear_repeat.name) };
            var static_samplers = [_][*c]graphics.Sampler{ linear_repeat.sampler };

            var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
            root_signature_desc.mStaticSamplerCount = static_samplers.len;
            root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
            root_signature_desc.ppStaticSamplers = @ptrCast(&static_samplers);
            root_signature_desc.mShaderCount = 1;
            root_signature_desc.ppShaders = @ptrCast(&shader);
            graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

            var render_targets = [_]graphics.TinyImageFormat{
                self.renderer.swap_chain.*.ppRenderTargets[0].*.mFormat,
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
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleCount = graphics.SampleCount.SAMPLE_COUNT_1;
            pipeline_desc.__union_field1.mGraphicsDesc.mSampleQuality = 0;
            pipeline_desc.__union_field1.mGraphicsDesc.pRootSignature = root_signature;
            pipeline_desc.__union_field1.mGraphicsDesc.pShaderProgram = shader;
            pipeline_desc.__union_field1.mGraphicsDesc.pVertexLayout = null;
            pipeline_desc.__union_field1.mGraphicsDesc.pRasterizerState = &rasterizer_cull_none;
            pipeline_desc.__union_field1.mGraphicsDesc.pBlendState = &blend_state_desc;
            graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

            const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
            self.pso_map.put(id, handle) catch unreachable;
        }

        // IBL Pipelines
        {
            const skybox = self.samplers.getSampler(StaticSamplers.skybox);
            const static_sampler_names = [_][*c]const u8{ @ptrCast(skybox.name) };
            const static_samplers = [_][*c]graphics.Sampler{ skybox.sampler };

            self.createComputePipeline(IdLocal.init("brdf_integration"), "brdf_integration.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
            self.createComputePipeline(IdLocal.init("compute_irradiance_map"), "compute_irradiance_map.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
            self.createComputePipeline(IdLocal.init("compute_specular_map"), "compute_specular_map.comp", @constCast(&static_samplers), @constCast(&static_sampler_names));
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

    fn createComputePipeline(self: *PSOManager, id: IdLocal, shader_name: []const u8, static_samplers: [][*c]graphics.Sampler, static_sampler_names: [][*c]const u8) void {
        var shader: [*c]graphics.Shader = null;
        var root_signature: [*c]graphics.RootSignature = null;
        var pipeline: [*c]graphics.Pipeline = null;

        var shader_load_desc = std.mem.zeroes(resource_loader.ShaderLoadDesc);
        shader_load_desc.mComp.pFileName = @ptrCast(shader_name);
        resource_loader.addShader(self.renderer.renderer, &shader_load_desc, &shader);

        var root_signature_desc = std.mem.zeroes(graphics.RootSignatureDesc);
        root_signature_desc.mStaticSamplerCount = @intCast(static_samplers.len);
        root_signature_desc.ppStaticSamplerNames = @ptrCast(&static_sampler_names);
        root_signature_desc.ppStaticSamplers = @ptrCast(static_samplers.ptr);
        root_signature_desc.mShaderCount = 1;
        root_signature_desc.ppShaders = @ptrCast(&shader);
        graphics.addRootSignature(self.renderer.renderer, &root_signature_desc, @ptrCast(&root_signature));

        var pipeline_desc = std.mem.zeroes(graphics.PipelineDesc);
        pipeline_desc.mType = graphics.PipelineType.PIPELINE_TYPE_COMPUTE;
        pipeline_desc.__union_field1.mComputeDesc.pShaderProgram = shader;
        pipeline_desc.__union_field1.mComputeDesc.pRootSignature = root_signature;
        graphics.addPipeline(self.renderer.renderer, &pipeline_desc, @ptrCast(&pipeline));

        const handle: PSOHandle = self.pso_pool.add(.{ .shader = shader, .root_signature = root_signature, .pipeline = pipeline }) catch unreachable;
        self.pso_map.put(id, handle) catch unreachable;
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
            graphics.addSampler(renderer, &desc, &sampler);
            static_samplers.samplers_map.put(linear_repeat, .{ .sampler = sampler, .name = "g_linear_repeat_sampler" }) catch unreachable;
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
            graphics.addSampler(renderer, &desc, &sampler);
            static_samplers.samplers_map.put(linear_clamp_edge, . { .sampler = sampler, .name = "g_linear_clamp_edge_sampler" }) catch unreachable;
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
            graphics.addSampler(renderer, &desc, &sampler);
            static_samplers.samplers_map.put(linear_clamp_border, . { .sampler = sampler, .name = "g_linear_clamp_border_sampler" }) catch unreachable;
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
            graphics.addSampler(renderer, &desc, &sampler);
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
            graphics.addSampler(renderer, &desc, &sampler);
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
            graphics.addSampler(renderer, &desc, &sampler);
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
            graphics.addSampler(renderer, &desc, &sampler);
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
