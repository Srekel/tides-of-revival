const std = @import("std");
const Graphics = @import("IGraphics.zig");

pub const GpuCmdRingDesc = struct {
    // Queue used to create the command pools
    queue: *Graphics.Queue,
    // Number of command pools in this ring
    pool_count: u32,
    // Number of command buffers to be created per command pool
    cmd_per_pool_count: u32,
    // Whether to add fence, semaphore for this ring
    add_sync_primitives: bool,
};

pub const GpuCmdRingElement = struct {
    cmd_pool: *Graphics.CmdPool,
    cmds: [*c][*c]Graphics.Cmd,
    fence: [*c]Graphics.Fence,
    semaphore: [*c]Graphics.Semaphore,
};

// Lightweight wrapper that works as a ring for command pools, command buffers
pub const GpuCmdRing = struct {
    pub const gpu_cmd_pools_per_ring_max: usize = 64;
    pub const gpu_cmds_per_pool_max: usize = 4;

    cmd_pools: [gpu_cmd_pools_per_ring_max]?*Graphics.CmdPool,
    cmds: [gpu_cmd_pools_per_ring_max][gpu_cmds_per_pool_max][*c]Graphics.Cmd,
    fences: [gpu_cmd_pools_per_ring_max][gpu_cmds_per_pool_max][*c]Graphics.Fence,
    semaphores: [gpu_cmd_pools_per_ring_max][gpu_cmds_per_pool_max][*c]Graphics.Semaphore,
    pool_index: u32,
    cmd_index: u32,
    fence_index: u32,
    pool_count: u32,
    cmd_per_pool_count: u32,

    pub fn create(renderer: *Graphics.Renderer, desc: *GpuCmdRingDesc) GpuCmdRing {
        std.debug.assert(desc.pool_count < gpu_cmd_pools_per_ring_max);
        std.debug.assert(desc.cmd_per_pool_count < gpu_cmds_per_pool_max);

        var gpu_cmd_ring: GpuCmdRing = undefined;
        gpu_cmd_ring.pool_count = desc.pool_count;
        gpu_cmd_ring.cmd_per_pool_count = desc.cmd_per_pool_count;

        var cmd_pool_desc = std.mem.zeroes(Graphics.CmdPoolDesc);
        cmd_pool_desc.mTransient = false;
        cmd_pool_desc.pQueue = desc.queue;

        var pool: usize = 0;
        while (pool < desc.pool_count) : (pool += 1) {
            Graphics.initCmdPool(renderer, &cmd_pool_desc, &gpu_cmd_ring.cmd_pools[pool]);

            var cmd_desc = std.mem.zeroes(Graphics.CmdDesc);
            cmd_desc.pPool = gpu_cmd_ring.cmd_pools[pool];

            var cmd: usize = 0;
            while (cmd < desc.cmd_per_pool_count) : (cmd += 1) {
                // TODO(gmodarelli): Check if debug graphics is enabled and set the cmd name
                Graphics.initCmd(renderer, &cmd_desc, &gpu_cmd_ring.cmds[pool][cmd]);

                if (desc.add_sync_primitives) {
                    Graphics.initFence(renderer, &gpu_cmd_ring.fences[pool][cmd]);
                    Graphics.initSemaphore(renderer, &gpu_cmd_ring.semaphores[pool][cmd]);
                }
            }
        }

        gpu_cmd_ring.pool_index = std.math.maxInt(u32);
        gpu_cmd_ring.cmd_index = std.math.maxInt(u32);
        gpu_cmd_ring.fence_index = std.math.maxInt(u32);

        return gpu_cmd_ring;
    }

    pub fn destroy(self: *GpuCmdRing, renderer: *Graphics.Renderer) void {
        var pool: usize = 0;
        while (pool < self.pool_count) : (pool += 1) {
            var cmd: usize = 0;
            while (cmd < self.cmd_per_pool_count) : (cmd += 1) {
                Graphics.exitCmd(renderer, self.cmds[pool][cmd]);
                if (self.semaphores[pool][cmd] != null) {
                    Graphics.exitSemaphore(renderer, self.semaphores[pool][cmd]);
                }

                if (self.fences[pool][cmd] != null) {
                    Graphics.exitFence(renderer, self.fences[pool][cmd]);
                }
            }

            Graphics.exitCmdPool(renderer, self.cmd_pools[pool]);
        }
    }

    pub fn getNextGpuCmdRingElement(self: *GpuCmdRing, cycle_pool: bool, cmd_count: u32) ?GpuCmdRingElement {
        if (cycle_pool) {
            if (self.pool_index == std.math.maxInt(u32)) {
                self.pool_index = 0;
            } else {
                self.pool_index = (self.pool_index + 1) % self.pool_count;
            }
            self.cmd_index = 0;
            self.fence_index = 0;
        }

        if (self.cmd_index + cmd_count < self.cmd_per_pool_count) {
            std.log.debug("Out of command buffers for this pool", .{});
            std.debug.assert(false);
            return null;
        }

        var elem: GpuCmdRingElement = undefined;
        elem.cmd_pool = self.cmd_pools[self.pool_index].?;
        elem.cmds = &self.cmds[self.pool_index][self.cmd_index];
        elem.fence = self.fences[self.pool_index][self.fence_index];
        elem.semaphore = self.semaphores[self.pool_index][self.fence_index];

        self.cmd_index += cmd_count;
        self.fence_index += 1;

        return elem;
    }
};
