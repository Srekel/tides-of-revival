const std = @import("std");
const zjobs = @import("zjobs");

const Jobs = zjobs.JobQueue(.{});

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");
const graph = @import("graph.zig");
const loaded_graph = @import("hill3.simgraph.zig");
// const loaded_graph = @import("testgraph.zig");
const graph_format = @import("graph_format.zig");

const SimulatorJob = struct {
    simulator: Simulator,
    pub fn exec(self: *@This()) void {
        self.simulator.simulate();
    }
};

const RunSimulationArgs = struct {
    self: *Simulator,
};

fn runSimulation(args: RunSimulationArgs) void {
    var self = args.self;

    self.mutex.lock();
    self.progress.percent = 0;
    self.mutex.unlock();

    const node_count = loaded_graph.node_count;
    // const node_count = loaded_graph.getGraph().nodes.len;
    var ctx = &self.ctx;

    loaded_graph.start(ctx);

    const time_start = std.time.milliTimestamp();
    while (ctx.next_nodes.len > 0) {
        const node_function = ctx.next_nodes.buffer[0];
        // std.log.debug("simulate: {any}\n\n", .{node_function});
        _ = ctx.next_nodes.orderedRemove(0);

        self.mutex.lock();
        self.progress.percent += 1.0 / @as(f32, @floatFromInt(node_count));
        self.mutex.unlock();

        const time_before = std.time.milliTimestamp();
        node_function(ctx);
        const time_after = std.time.milliTimestamp();
        const node_duration = time_after - time_before;
        const total_duration = time_after - time_start;
        std.log.debug("Node: {d:>5} ms, Total: {d:>6.1} s", .{
            @as(f32, @floatFromInt(node_duration)) / 1,
            @as(f32, @floatFromInt(total_duration)) / std.time.ms_per_s,
        });
    }

    loaded_graph.exit(ctx);

    self.mutex.lock();
    self.progress.percent = 1;
    self.thread = null;
    self.mutex.unlock();
}

pub const Simulator = struct {
    mutex: std.Thread.Mutex = .{},
    progress: SimulatorProgress = .{},
    jobs: Jobs = .{},
    thread: ?std.Thread = null,
    ctx: graph.Context = undefined,

    pub fn init(self: *Simulator) void {
        cpp_nodes.init();
        self.progress.percent = 0;
        self.jobs = Jobs.init();

        self.ctx = .{};
        self.ctx.resources = std.StringHashMap(*anyopaque).init(std.heap.c_allocator); // TODO fix
        self.ctx.resources.ensureTotalCapacity(1024) catch unreachable;
        self.ctx.previews = std.StringHashMap(graph.Preview).init(std.heap.c_allocator); // TODO fix
        self.ctx.previews.ensureTotalCapacity(1024) catch unreachable;

        graph_format.generateFile("../../../../content/world/hill3/hill3.simgraph.json5", "../../src/sim/hill3.simgraph");
        // graph_format.generateFile("../../../../content/world/hill3/hill3.simgraph.json5", "../../../../content/world/hill3/hill3.simgraph");
        // std.process.exit(0);
    }

    pub fn deinit(self: *Simulator) void {
        cpp_nodes.deinit();
        self.jobs.deinit();
    }

    pub fn simulate(self: *Simulator) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.thread != null) {
            return;
        }

        self.thread = std.Thread.spawn(.{}, runSimulation, .{RunSimulationArgs{ .self = self }}) catch unreachable;
    }

    pub fn simulateSteps(self: *Simulator, steps: u32) void {
        _ = self; // autofix
        _ = steps; // autofix
        // if (self.next_nodes.len == 0) {
        //     self.next_nodes.appendAssumeCapacity(loaded_graph.start());
        // }

        // for (0..steps) |_| {
        //     if (self.next_nodes.len > 0) {
        //         const node_function = self.next_nodes.buffer[0];
        //         std.log.debug("simulate \n{any}\n\n", .{node_function});
        //         _ = self.next_nodes.orderedRemove(0);
        //         node_function(self);
        //     }
        // }
    }

    pub fn getPreview(self: *Simulator, resource_name: []const u8, image_width: u32, image_height: u32) ?[]u8 {
        _ = image_width; // autofix
        _ = image_height; // autofix
        self.mutex.lock();
        defer self.mutex.unlock();
        if (!self.ctx.previews.contains(resource_name)) {
            return null;
        }
        return self.ctx.previews.get(resource_name).?.data;
    }

    pub fn getProgress(self: *Simulator) SimulatorProgress {
        self.mutex.lock();
        const progress = self.progress;
        self.mutex.unlock();
        return progress;
    }
};

pub const SimulatorProgress = struct {
    percent: f32 = 0,
};
