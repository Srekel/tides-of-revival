const std = @import("std");
const zjobs = @import("zjobs");

const Jobs = zjobs.JobQueue(.{});

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");
const graph = @import("graph.zig");
const loaded_graph = @import("testgraph.zig");

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

    const node_count = 4;
    var ctx = &self.ctx;

    // TODO: Move into global graph (?)
    const c_cpp_nodes = @cImport({
        @cInclude("world_generator.h");
    });
    var map_settings: c_cpp_nodes.MapSettings = .{};
    map_settings.seed = 100;
    map_settings.size = 8;
    ctx.resources.putAssumeCapacity("map", &map_settings);

    loaded_graph.start(ctx);

    while (ctx.next_nodes.len > 0) {
        const node_function = ctx.next_nodes.buffer[0];
        std.log.debug("simulate \n{any}\n\n", .{node_function});
        _ = ctx.next_nodes.orderedRemove(0);

        self.mutex.lock();
        self.progress.percent += @as(f32, 1.0) / node_count;
        self.mutex.unlock();

        node_function(ctx);
    }
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

    pub fn getPreview(self: *Simulator, image_width: u32, image_height: u32) []u8 {
        _ = image_width; // autofix
        _ = image_height; // autofix
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.ctx.previews.get("beaches.grid").?.data;
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
