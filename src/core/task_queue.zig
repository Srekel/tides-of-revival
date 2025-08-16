const std = @import("std");
const zpool = @import("zpool");
const IdLocal = @import("core.zig").IdLocal;

const context = @import("context.zig");
const ecsu = @import("../flecs_util/flecs_util.zig");
const zphy = @import("zphysics");
const prefab_manager = @import("../prefab_manager.zig");
const util = @import("../util.zig");

pub const QueueLoopType = union(enum) {
    once: void,
    loop: f64,
};

pub const TaskTimeInfo = struct {
    time: f64,
    loop_type: QueueLoopType = .{ .once = {} },
};

pub fn NoOpTaskFunc(data: []u8) void {
    _ = data; // autofix
}

pub const TaskContext = struct {
    pub usingnamespace context.CONTEXTIFY(@This());
    heap_allocator: std.mem.Allocator,
    ecsu_world: ecsu.World,
    physics_world: *zphy.PhysicsSystem,
    physics_world_low: *zphy.PhysicsSystem,
    prefab_mgr: *prefab_manager.PrefabManager,
    task_queue: *TaskQueue,
    time: *util.GameTime,
};

pub const TaskType = struct {
    pub const TaskFunc = fn (ctx: TaskContext, data: []u8, allocator: std.mem.Allocator) void;

    id: IdLocal,
    setup: *const TaskFunc,
    calculate: *const TaskFunc,
    apply: *const TaskFunc,
};

const Task = struct {
    id: IdLocal,
    data: []u8,

    time_info: TaskTimeInfo, // TODO: Move to parallell array(s) / pool
};

pub const TaskQueue = struct {
    const ArrayChunk = struct {
        start_time: f64 = undefined,
        tasks: [chunk_size]Task = undefined,
        count: u8 = 0,
    };

    const chunk_size = 256;

    // TODO: Poolify
    allocator: std.mem.Allocator,
    ctx: TaskContext,

    queued_chunks: std.ArrayListUnmanaged(*ArrayChunk),
    free_chunks: std.ArrayListUnmanaged(*ArrayChunk),
    tasks_to_setup: std.ArrayListUnmanaged(Task),
    tasks_to_calculate: std.ArrayListUnmanaged(Task),
    tasks_to_apply: std.ArrayListUnmanaged(Task),

    task_types: std.AutoArrayHashMapUnmanaged(IdLocal.HashType, TaskType),

    pub fn init(self: *TaskQueue, allocator: std.mem.Allocator, ctx: anytype) void {
        self.allocator = allocator;
        self.queued_chunks = .{};
        self.free_chunks = .{};
        self.ctx = TaskContext.view(ctx);

        self.queued_chunks = std.ArrayListUnmanaged(*ArrayChunk).initCapacity(allocator, 8) catch unreachable; // low for now
        self.free_chunks = std.ArrayListUnmanaged(*ArrayChunk).initCapacity(allocator, 8) catch unreachable; // low for now
        self.tasks_to_setup = std.ArrayListUnmanaged(Task).initCapacity(allocator, 8) catch unreachable; // low for now
        self.tasks_to_calculate = std.ArrayListUnmanaged(Task).initCapacity(allocator, 8) catch unreachable; // low for now
        self.tasks_to_apply = std.ArrayListUnmanaged(Task).initCapacity(allocator, 8) catch unreachable; // low for now
        self.task_types = std.AutoArrayHashMapUnmanaged(IdLocal.HashType, TaskType).init(allocator, &.{}, &.{}) catch unreachable; // low for now
    }

    pub fn registerTaskType(self: *TaskQueue, task_type: TaskType) void {
        self.task_types.put(self.allocator, task_type.id.hash, task_type) catch unreachable;
    }

    pub fn allocateTaskData(self: *TaskQueue, time: f64, comptime TaskDataType: type) *TaskDataType {
        _ = time; // autofix

        const task_data = self.allocator.create(TaskDataType) catch unreachable;
        return task_data;
    }

    pub fn enqueue(self: *TaskQueue, id: IdLocal, time_info: TaskTimeInfo, task_data: []u8) void {
        const chunk = blk: {
            for (self.queued_chunks.items) |chunk| {
                if (chunk.start_time < time_info.time) {
                    break :blk chunk;
                }
            } else {
                const chunk = self.grabFreeChunk();
                self.queued_chunks.append(self.allocator, chunk) catch unreachable;
                break :blk chunk;
            }
        };

        var insert_chunk = chunk;
        if (chunk.count == chunk_size) {
            // split chunk into two chunks, lc and rc, down middle
            const lc = chunk; // left chunk
            const rc = self.grabFreeChunk(); // right chunk
            for (chunk_size / 2..chunk_size, 0..chunk_size / 2) |i_lc, i_rc| {
                // TODO: memcpy
                rc[i_rc] = lc[i_lc];
            }

            lc.count = chunk_size / 2;
            rc.count = chunk_size / 2;
            rc.start_time = rc.tasks[0].time;

            // TODO: Insert at right place
            std.debug.assert(false);

            insert_chunk = if (rc.start_time < time_info.time) rc else lc;
        }

        var task_index = insert_chunk.count;
        for (0..insert_chunk.count) |i_c| {
            const task = &insert_chunk.tasks[i_c];
            if (task.time_info.time > time_info.time) {
                std.mem.copyBackwards(Task, insert_chunk.tasks[i_c + 1 .. insert_chunk.count + 1], insert_chunk.tasks[i_c..insert_chunk.count]);
                task_index = @intCast(i_c);
                break;
            }
        }

        const task = &insert_chunk.tasks[task_index];
        task.* = .{
            .time_info = time_info,
            .data = task_data,
            .id = id,
        };

        insert_chunk.count += 1;
    }

    pub fn findTasksToSetup(self: *TaskQueue, time: f64) void {
        for (self.queued_chunks.items) |chunk| {
            var found_tasks_to_setup: u8 = 0;
            for (chunk.tasks[0..chunk.count]) |task| {
                if (task.time_info.time > time) {
                    break;
                }

                found_tasks_to_setup += 1;
                self.tasks_to_setup.append(self.allocator, task) catch unreachable;
            }

            if (found_tasks_to_setup == 0) {
                break;
            }

            const new_count = chunk.count - found_tasks_to_setup;
            if (new_count != 0) {
                std.mem.copyForwards(Task, chunk.tasks[0..new_count], chunk.tasks[found_tasks_to_setup .. chunk.count - found_tasks_to_setup + 1]);
            }
            chunk.count = new_count;
        }

        while (self.queued_chunks.items.len > 0 and self.queued_chunks.items[0].count == 0) {
            self.free_chunks.append(self.allocator, self.queued_chunks.items[0]) catch unreachable;
            _ = self.queued_chunks.orderedRemove(0);
        }
    }

    pub fn setupTasks(self: *TaskQueue) void {
        self.tasks_to_calculate.appendSlice(self.allocator, self.tasks_to_setup.items) catch unreachable;

        const i_task: u32 = 0;
        while (i_task < self.tasks_to_setup.items.len) {
            const task = &self.tasks_to_setup.items[i_task];
            const task_type = self.task_types.get(task.id.hash).?;
            const allocator = self.ctx.heap_allocator; // temp
            task_type.setup(self.ctx, task.data, allocator);

            switch (task.time_info.loop_type) {
                .once => {
                    _ = self.tasks_to_setup.swapRemove(i_task);
                },
                .loop => {
                    self.enqueue(
                        task.id,
                        .{
                            .time = task.time_info.time + task.time_info.loop_type.loop,
                            .loop_type = task.time_info.loop_type,
                        },
                        task.data, // LOL FIX
                    );
                    _ = self.tasks_to_setup.swapRemove(i_task);
                },
            }
        }
    }

    pub fn calculateTasks(self: *TaskQueue) void {
        for (self.tasks_to_calculate.items) |*task| {
            const task_type = self.task_types.get(task.id.hash).?;
            const allocator = self.ctx.heap_allocator; // temp
            task_type.calculate(self.ctx, task.data, allocator);
        }

        self.tasks_to_apply.appendSlice(self.allocator, self.tasks_to_calculate.items) catch unreachable;
        self.tasks_to_calculate.clearRetainingCapacity();
    }

    pub fn applyTasks(self: *TaskQueue) void {
        for (self.tasks_to_apply.items) |*task| {
            const task_type = self.task_types.get(task.id.hash).?;
            const allocator = self.ctx.heap_allocator; // temp
            task_type.apply(self.ctx, task.data, allocator);
        }

        self.tasks_to_apply.clearRetainingCapacity();
    }

    fn grabFreeChunk(self: *TaskQueue) *ArrayChunk {
        if (self.free_chunks.items.len == 0) {
            const chunk = self.allocator.create(ArrayChunk) catch unreachable;
            chunk.* = .{};
            self.free_chunks.append(self.allocator, chunk) catch unreachable;
        }
        const chunk = self.free_chunks.pop().?;
        chunk.count = 0;
        return chunk;
    }
};
