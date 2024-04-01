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

pub const TonemapRenderPass = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    descriptor_set: [*c]graphics.DescriptorSet,

    pub fn create(rctx: *renderer.Renderer, ecsu_world: ecsu.World, allocator: std.mem.Allocator) *TonemapRenderPass {
        var descriptor_set: [*c]graphics.DescriptorSet = undefined;
        {
            const root_signature = rctx.getRootSignature(IdLocal.init("tonemapper"));
            var desc = std.mem.zeroes(graphics.DescriptorSetDesc);
            desc.mUpdateFrequency = graphics.DescriptorUpdateFrequency.DESCRIPTOR_UPDATE_FREQ_NONE;
            desc.mMaxSets = renderer.Renderer.data_buffer_count;
            desc.pRootSignature = root_signature;
            graphics.addDescriptorSet(rctx.renderer, &desc, @ptrCast(&descriptor_set));
        }

        const pass = allocator.create(TonemapRenderPass) catch unreachable;
        pass.* = .{
            .allocator = allocator,
            .ecsu_world = ecsu_world,
            .renderer = rctx,
            .descriptor_set = descriptor_set,
        };

        prepareDescriptorSets(@ptrCast(pass));

        return pass;
    }

    pub fn destroy(self: *TonemapRenderPass) void {
        graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
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
pub const prepareDescriptorSetsFn: renderer.renderPassPrepareDescriptorSetsFn = prepareDescriptorSets;
pub const unloadDescriptorSetsFn: renderer.renderPassUnloadDescriptorSetsFn = unloadDescriptorSets;

fn render(cmd_list: [*c]graphics.Cmd, user_data: *anyopaque) void {
    const trazy_zone = ztracy.ZoneNC(@src(), "Skybox Render Pass", 0x00_ff_ff_00);
    defer trazy_zone.End();

    const self: *TonemapRenderPass = @ptrCast(@alignCast(user_data));

    const pipeline_id = IdLocal.init("tonemapper");
    const pipeline = self.renderer.getPSO(pipeline_id);

    graphics.cmdBindPipeline(cmd_list, pipeline);
    graphics.cmdBindDescriptorSet(cmd_list, 0, self.descriptor_set);

    graphics.cmdDraw(cmd_list, 3, 0);
}

fn prepareDescriptorSets(user_data: *anyopaque) void {
    const self: *TonemapRenderPass = @ptrCast(@alignCast(user_data));

    for (0..renderer.Renderer.data_buffer_count) |i| {
        var params: [1]graphics.DescriptorData = undefined;

        params[0] = std.mem.zeroes(graphics.DescriptorData);
        params[0].pName = "sceneColor";
        params[0].__union_field3.ppTextures = @ptrCast(&self.renderer.scene_color.*.pTexture);
        graphics.updateDescriptorSet(self.renderer.renderer, 0, self.descriptor_set, @intCast(i), @ptrCast(&params));
    }
}

fn unloadDescriptorSets(user_data: *anyopaque) void {
    const self: *TonemapRenderPass = @ptrCast(@alignCast(user_data));

    graphics.removeDescriptorSet(self.renderer.renderer, self.descriptor_set);
}
