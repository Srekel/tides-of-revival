const std = @import("std");

const context = @import("../core/context.zig");
const ecs = @import("zflecs");
const ecsu = @import("../flecs_util/flecs_util.zig");
const fd = @import("../config/flecs_data.zig");
const IdLocal = @import("../core/core.zig").IdLocal;
const renderer = @import("../renderer/renderer.zig");
const zforge = @import("zforge");

const font = zforge.font;
const graphics = zforge.graphics;
const resource_loader = zforge.resource_loader;

pub const SystemState = struct {
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
    sys: ecs.entity_t,
};

pub const SystemCtx = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    renderer: *renderer.Renderer,
};

pub fn create(name: IdLocal, ctx: SystemCtx) !*SystemState {
    const system = ctx.allocator.create(SystemState) catch unreachable;
    const sys = ctx.ecsu_world.newWrappedRunSystem(name.toCString(), ecs.PostUpdate, fd.NOCOMP, update, .{ .ctx = system });

    system.* = .{
        .allocator = ctx.allocator,
        .ecsu_world = ctx.ecsu_world,
        .renderer = ctx.renderer,
        .sys = sys,
    };

    return system;
}

pub fn destroy(system: *SystemState) void {
    system.allocator.destroy(system);
}

// ██╗   ██╗██████╗ ██████╗  █████╗ ████████╗███████╗
// ██║   ██║██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝██╔════╝
// ██║   ██║██████╔╝██║  ██║███████║   ██║   █████╗
// ██║   ██║██╔═══╝ ██║  ██║██╔══██║   ██║   ██╔══╝
// ╚██████╔╝██║     ██████╔╝██║  ██║   ██║   ███████╗
//  ╚═════╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝

fn update(iter: *ecsu.Iterator(fd.NOCOMP)) void {
    defer ecs.iter_fini(iter.iter);
    const system: *SystemState = @ptrCast(@alignCast(iter.iter.ctx));
    var rctx = system.renderer;

    if (rctx.window.frame_buffer_size[0] != rctx.window_width or rctx.window.frame_buffer_size[1] != rctx.window_height) {
        rctx.window_width = rctx.window.frame_buffer_size[0];
        rctx.window_height = rctx.window.frame_buffer_size[1];

        const reload_desc = graphics.ReloadDesc{ .mType = .{ .RESIZE = true } };
        rctx.onUnload(reload_desc);
        rctx.onLoad(reload_desc) catch unreachable;
    }

    draw(rctx);
}

// ██████╗ ██████╗  █████╗ ██╗    ██╗
// ██╔══██╗██╔══██╗██╔══██╗██║    ██║
// ██║  ██║██████╔╝███████║██║ █╗ ██║
// ██║  ██║██╔══██╗██╔══██║██║███╗██║
// ██████╔╝██║  ██║██║  ██║╚███╔███╔╝
// ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚══╝╚══╝

fn draw(rctx: *renderer.Renderer) void {
    var swap_chain_image_index: u32 = 0;
    graphics.acquireNextImage(rctx.renderer, rctx.swap_chain, rctx.image_acquired_semaphore, null, &swap_chain_image_index);
    const render_target = rctx.swap_chain.*.ppRenderTargets[swap_chain_image_index];

    var elem = rctx.gpu_cmd_ring.getNextGpuCmdRingElement(true, 1).?;

    // Stall if CPU is running "data_buffer_count" frames ahead of GPU
    var fence_status: graphics.FenceStatus = undefined;
    graphics.getFenceStatus(rctx.renderer, elem.fence, &fence_status);
    if (fence_status.bits == graphics.FenceStatus.FENCE_STATUS_INCOMPLETE.bits) {
        graphics.waitForFences(rctx.renderer, 1, &elem.fence);
    }

    graphics.resetCmdPool(rctx.renderer, elem.cmd_pool);

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
    graphics.cmdSetViewport(cmd, 0.0, 0.0, @floatFromInt(rctx.window.frame_buffer_size[0]), @floatFromInt(rctx.window.frame_buffer_size[1]), 0.0, 1.0);
    graphics.cmdSetScissor(cmd, 0, 0, @intCast(rctx.window.frame_buffer_size[0]), @intCast(rctx.window.frame_buffer_size[1]));

    var font_draw_desc = std.mem.zeroes(font.FontDrawDesc);
    font_draw_desc.pText = "Z-Forge !11!!";
    font_draw_desc.mFontID = rctx.roboto_font_id;
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

    var wait_semaphores = [2]*graphics.Semaphore{ flush_update_desc.pOutSubmittedSemaphore, rctx.image_acquired_semaphore };

    var submit_desc: graphics.QueueSubmitDesc = undefined;
    submit_desc.mCmdCount = 1;
    submit_desc.mSignalSemaphoreCount = 1;
    submit_desc.mWaitSemaphoreCount = 2;
    submit_desc.ppCmds = &cmd;
    submit_desc.ppSignalSemaphores = &elem.semaphore;
    submit_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
    submit_desc.pSignalFence = elem.fence;
    graphics.queueSubmit(rctx.graphics_queue, &submit_desc);

    var queue_present_desc: graphics.QueuePresentDesc = undefined;
    queue_present_desc.mIndex = @intCast(swap_chain_image_index);
    queue_present_desc.mWaitSemaphoreCount = 1;
    queue_present_desc.pSwapChain = rctx.swap_chain;
    queue_present_desc.ppWaitSemaphores = @ptrCast(&wait_semaphores);
    queue_present_desc.mSubmitDone = true;
    graphics.queuePresent(rctx.graphics_queue, &queue_present_desc);

    rctx.frame_index = (rctx.frame_index + 1) % renderer.Renderer.data_buffer_count;
}
