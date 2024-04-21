const std = @import("std");

const ecs = @import("zflecs");
const ecsu = @import("../../flecs_util/flecs_util.zig");
const fd = @import("../../config/flecs_data.zig");
const IdLocal = @import("../../core/core.zig").IdLocal;
const renderer = @import("../../renderer/renderer.zig");
const zforge = @import("zforge");
const ztracy = @import("ztracy");
const util = @import("../../util.zig");
const zm = @import("zmath");

const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

const UniformFrameData = struct {
    projection_view: [16]f32,
    projection_view_inverted: [16]f32,
    camera_position: [4]f32,
};

pub const SkyboxRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,

    needs_to_udate_descriptors: bool,
    uniform_frame_data: UniformFrameData,
    uniform_frame_buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle,
    descriptor_sets: [2][*c]graphics.DescriptorSet,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *SkyboxRenderPass {
        const uniform_frame_buffers = blk: {
            var buffers: [renderer.Renderer.data_buffer_count]renderer.BufferHandle = undefined;
            for (buffers, 0..) |_, buffer_index| {
                buffers[buffer_index] = rctx.createUniformBuffer(UniformFrameData);
            }

            break :blk buffers;
        };

        const pass = allocator.create(SkyboxRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .needs_to_udate_descriptors = true,
            .descriptor_sets = undefined,
            .uniform_frame_data = std.mem.zeroes(UniformFrameData),
            .uniform_frame_buffers = uniform_frame_buffers,
        };

        createDescriptorSets(@ptrCast(pass));
        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *SkyboxRenderPass) void {
        for (self.descriptor_sets) |descriptor_set| {
            graphics.removeDescriptorSet(self.renderer.renderer, descriptor_set);
        }

        self.allocator.destroy(self);
    }
};

// ██████╗ ███████╗███╗   ██╗██████╗ ███████╗██████╗
// ██╔══██╗██╔════╝████╗  ██║██╔══██╗██╔════╝██╔══██╗
// ██████╔╝█████╗  ██╔██╗ ██║██║  ██║█████╗  ██████╔╝
// ██╔══██╗██╔══╝  ██║╚██╗██║██║  ██║██╔══╝  ██╔══██╗
// ██║  ██║███████╗██║ ╚████║██████╔╝███████╗██║  ██║
// ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚═╝  ╚═╝

pub const renderFn: renderer.renderPassRenderFn = render;
pub const createDescriptorSetsFn: renderer.renderPassCreateDescriptorSetsFn = createDescriptorSets;
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Skybox Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *SkyboxRenderPass = @ptrCast(@alignCast(user_data));

    const frame_index = self.renderer.frame_index;

    var camera_entity = util.getActiveCameraEnt(self.ecsu_world);
    const camera_comps = camera_entity.getComps(struct {
        camera: *const fd.Camera,
        transform: *const fd.Transform,
    });
    const camera_position = camera_comps.transform.getPos00();
    var z_view = zm.loadMat(camera_comps.camera.view[0..]);
    // Set translation to 0, 0, 0
    z_view[3][0] = 0.0;
    z_view[3][1] = 0.0;
    z_view[3][2] = 0.0;
    const z_proj = zm.loadMat(camera_comps.camera.projection[0..]);
    const z_proj_view = zm.mul(z_view, z_proj);

    zm.storeMat(&self.uniform_frame_data.projection_view, z_proj_view);
    zm.storeMat(&self.uniform_frame_data.projection_view_inverted, zm.inverse(z_proj_view));
    self.uniform_frame_data.camera_position = [4]f32{ camera_position[0], camera_position[1], camera_position[2], 1.0 };

    const data = renderer.Slice{
        .data = @ptrCast(&self.uniform_frame_data),
        .size = @sizeOf(UniformFrameData),
    };
    self.renderer.updateBuffer(data, UniformFrameData, self.uniform_frame_buffers[frame_index]);

    const sky_light_entity = util.getSkyLight(self.ecsu_world);
    if (sky_light_entity) |sky_light| {
        const sky_light_comps = sky_light.getComps(struct {
            sky_light: *const fd.SkyLight,
        });

        if (self.needs_to_udate_descriptors) {
            prepareDescriptorSets(@ptrCast(self));
        }

        const mesh = self.renderer.getMesh(sky_light_comps.sky_light.mesh);

        const pipeline_id = IdLocal.init("skybox");
        const pipeline = self.renderer.getPSO(pipeline_id);

        graphics.cmdBindPipeline(cmd_list, pipeline);
        graphics.cmdBindDescriptorSet(cmd_list, 0, self.descriptor_sets[0]);
        graphics.cmdBindDescriptorSet(cmd_list, frame_index, self.descriptor_sets[1]);

        if (mesh.loaded) {
            const vertex_buffers = [_][*c]graphics.Buffer{
                mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.POSITION)]].pBuffer,
                mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.NORMAL)]].pBuffer,
                mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TANGENT)]].pBuffer,
                mesh.buffer.*.mVertex[mesh.buffer_layout_desc.mSemanticBindings[@intFromEnum(graphics.ShaderSemantic.TEXCOORD0)]].pBuffer,
            };

            graphics.cmdBindVertexBuffer(cmd_list, vertex_buffers.len, @constCast(&vertex_buffers), @constCast(&mesh.geometry.*.mVertexStrides), null);
            graphics.cmdBindIndexBuffer(cmd_list, mesh.buffer.*.mIndex.pBuffer, mesh.geometry.*.bitfield_1.mIndexType, 0);
            graphics.cmdDrawIndexed(
                cmd_list,
                mesh.geometry.*.pDrawArgs[0].mIndexCount,
                mesh.geometry.*.pDrawArgs[0].mStartIndex,
                mesh.geometry.*.pDrawArgs[0].mVertexOffset,
            );
        }
    }
}

fn createDescriptorSets(user_data: *anyopaque) void {
    const self: *SkyboxRenderPass = @ptrCast(@alignCast(user_data));

    var descriptor_sets: [2][*c]graphics.DescriptorSet = undefined;
    {
        const root_signature = self.renderer.getRootSignature(IdLocal.init("skybox"));
        var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
        desc.mMaxSets = 1;
        desc.pRootSignature = root_signature;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets[0]));

        desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_PER_FRAME;
        desc.mMaxSets = renderer.Renderer.data_buffer_count;
        graphics.addDescriptorSet(self.renderer.renderer, &desc, @ptrCast(&descriptor_sets[1]));
    }
    self.descriptor_sets = descriptor_sets;
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *SkyboxRenderPass = @ptrCast(@alignCast(user_data));

    const sky_light_entity = util.getSkyLight(self.ecsu_world);
    if (sky_light_entity) |sky_light| {
        const sky_light_comps = sky_light.getComps(struct {
            sky_light: *const fd.SkyLight,
        });

        var hdri_texture = self.renderer.getTexture(sky_light_comps.sky_light.hdri);
        self.needs_to_udate_descriptors = false;

        var params: [1]graphics.DescriptorData = undefined;

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "skyboxMap";
        params[0].__union_field3.ppTextures = @ptrCast(&hdri_texture);
        graphics.updateDescriptorSet(self.renderer.renderer, 0, self.descriptor_sets[0], 1, @ptrCast(&params));

        for (0..renderer.Renderer.data_buffer_count) |i| {
            var uniform_buffer = self.renderer.getBuffer(self.uniform_frame_buffers[i]);
            params[0] = std.mem.zeroes(graphics.DescriptorData);
            params[0].pName = "cbFrame";
            params[0].__union_field3.ppBuffers = @ptrCast(&uniform_buffer);

            graphics.updateDescriptorSet(self.renderer.renderer, @intCast(i), self.descriptor_sets[1], 1, @ptrCast(&params));
        }
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *SkyboxRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets[0]);
    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_sets[1]);
}
