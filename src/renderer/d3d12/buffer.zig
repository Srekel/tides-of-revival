const std = @import("std");
const assert = std.debug.assert;
const zwin32 = @import("zwin32");
const d3d12 = zwin32.d3d12;
const zd3d12 = @import("zd3d12");

pub const BufferDesc = struct {
    size: u64,
    state: d3d12.RESOURCE_STATES, // TODO: Replace this with non-d3d12 state enum
    name: [*:0]const u16,
    // TODO: Convert these bools to a flag
    persistent: bool,
    has_cbv: bool,
    has_srv: bool,
    has_uav: bool,
};

pub const Buffer = struct {
    size: u64,
    state: d3d12.RESOURCE_STATES, // TODO: Replace this with non-d3d12 state enum
    // TODO: Convert these bools to a flag
    persistent: bool,
    has_cbv: bool,
    has_srv: bool,
    has_uav: bool,

    resource: zd3d12.ResourceHandle,
    persistent_descriptor: zd3d12.PersistentDescriptor,
};

pub const BufferHandle = struct {
    index: u16 align(4) = 0,
    generation: u16 = 0,
};

pub const BufferPool = struct {
    const max_num_buffers = 256; // TODO: Figure out how many we need as we go

    buffers: []Buffer,
    generations: []u16,

    pub fn init(allocator: std.mem.Allocator) BufferPool {
        return .{
            .buffers = blk: {
                var buffers = allocator.alloc(
                    Buffer,
                    max_num_buffers + 1,
                ) catch unreachable;
                for (buffers) |*buffer| {
                    buffer.* = .{
                        .size = 0,
                        .state = d3d12.RESOURCE_STATES.COMMON,
                        .persistent = false,
                        .has_cbv = false,
                        .has_srv = false,
                        .has_uav = false,
                        .resource = undefined,
                        .persistent_descriptor = undefined,
                    };
                }
                break :blk buffers;
            },
            .generations = blk: {
                var generations = allocator.alloc(
                    u16,
                    max_num_buffers + 1,
                ) catch unreachable;
                for (generations) |*gen| gen.* = 0;
                break :blk generations;
            },
        };
    }

    pub fn deinit(pool: *BufferPool, allocator: std.mem.Allocator, gctx: *zd3d12.GraphicsContext) void {
        for (pool.buffers) |buffer| {
            if (buffer.size > 0) {
                gctx.destroyResource(buffer.resource);
            }
        }

        allocator.free(pool.buffers);
        allocator.free(pool.generations);
        pool.* = undefined;
    }

    pub fn addBuffer(pool: *BufferPool, buffer: Buffer) BufferHandle {
        var slot_idx: u32 = 1;
        while (slot_idx <= max_num_buffers) : (slot_idx += 1) {
            if (pool.buffers[slot_idx].size == 0)
                break;
        }
        assert(slot_idx <= max_num_buffers);

        pool.buffers[slot_idx] = .{
            .size = buffer.size,
            .state = buffer.state,
            .persistent = buffer.persistent,
            .has_cbv = buffer.has_cbv,
            .has_srv = buffer.has_srv,
            .has_uav = buffer.has_uav,
            .resource = buffer.resource,
            .persistent_descriptor = .{
                .cpu_handle = buffer.persistent_descriptor.cpu_handle,
                .gpu_handle = buffer.persistent_descriptor.gpu_handle,
                .index = buffer.persistent_descriptor.index,
            },
        };
        const handle = BufferHandle{
            .index = @as(u16, @intCast(slot_idx)),
            .generation = blk: {
                pool.generations[slot_idx] += 1;
                break :blk pool.generations[slot_idx];
            },
        };
        return handle;
    }

    pub fn destroyBuffer(pool: *BufferPool, handle: BufferHandle, gctx: *zd3d12.GraphicsContext) void {
        var buffer = pool.lookupBuffer(handle);
        if (buffer == null)
            return;

        gctx.destroyResource(buffer.?.resource);

        buffer.?.* = .{
            .size = 0,
            .state = d3d12.RESOURCE_STATES.COMMON,
            .persistent = false,
            .has_cbv = false,
            .has_srv = false,
            .has_uav = false,
            .resource = undefined,
            .persistent_descriptor = undefined,
        };
    }

    fn isBufferValid(pool: BufferPool, handle: BufferHandle) bool {
        return handle.index > 0 and
            handle.index <= max_num_buffers and
            handle.generation > 0 and
            handle.generation == pool.generations[handle.index] and
            pool.buffers[handle.index].size > 0;
    }

    pub fn lookupBuffer(pool: BufferPool, handle: BufferHandle) ?*Buffer {
        if (pool.isBufferValid(handle)) {
            return &pool.buffers[handle.index];
        }

        return null;
    }
};
