const std = @import("std");
const zjobs = @import("zjobs");

const Jobs = zjobs.JobQueue(.{});

const cpp_nodes = @import("../sim_cpp/cpp_nodes.zig");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

const fn_node = *const fn (self: *Simulator) void;

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

    const node_count = 2;

    while (self.next_nodes.len > 0) {
        self.mutex.lock();
        self.progress.percent += @as(f32, 1.0) / node_count;
        self.mutex.unlock();

        const node_function = self.next_nodes.buffer[0];
        std.log.debug("simulate \n{any}\n\n", .{node_function});
        _ = self.next_nodes.orderedRemove(0);
        node_function(self);
    }
    self.mutex.lock();
    self.progress.percent = 1;
    self.thread = null;
    self.mutex.unlock();
}

pub const Simulator = struct {
    next_nodes: std.BoundedArray(fn_node, 16) = .{},
    mutex: std.Thread.Mutex = .{},
    progress: SimulatorProgress = .{},
    jobs: Jobs = .{},
    thread: ?std.Thread = null,

    grid: c_cpp_nodes.Grid = undefined,
    map_settings: c_cpp_nodes.MapSettings = undefined,
    voronoi_settings: c_cpp_nodes.VoronoiSettings = undefined,

    pub fn init(self: *Simulator) void {
        cpp_nodes.init();
        self.progress.percent = 0;
        self.jobs = Jobs.init();

        self.map_settings.size = 8.0;
        self.map_settings.seed = 1981;
        self.voronoi_settings.radius = 0.05;
        self.voronoi_settings.num_relaxations = 10;
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

        self.next_nodes.appendAssumeCapacity(doNode_GenerateVoronoiMap1);
        self.thread = std.Thread.spawn(.{}, runSimulation, .{RunSimulationArgs{ .self = self }}) catch unreachable;
    }

    pub fn simulateSteps(self: *Simulator, steps: u32) void {
        if (self.next_nodes.len == 0) {
            self.next_nodes.appendAssumeCapacity(doNode_GenerateVoronoiMap1);
        }

        for (0..steps) |_| {
            if (self.next_nodes.len > 0) {
                const node_function = self.next_nodes.buffer[0];
                std.log.debug("simulate \n{any}\n\n", .{node_function});
                _ = self.next_nodes.orderedRemove(0);
                node_function(self);
            }
        }
    }

    pub fn getPreview(self: *Simulator, image_width: u32, image_height: u32) [*c]u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.thread != null) {
            return null;
        }
        return cpp_nodes.generate_landscape_preview(&self.grid, image_width, image_height);
    }

    pub fn getProgress(self: *Simulator) SimulatorProgress {
        self.mutex.lock();
        const progress = self.progress;
        self.mutex.unlock();
        return progress;
    }

    fn doNode_GenerateVoronoiMap1(self: *Simulator) void {
        cpp_nodes.generate_voronoi_map(&self.map_settings, &self.voronoi_settings, &self.grid);
        self.next_nodes.appendAssumeCapacity(doNode_generate_landscape_from_image);
    }

    fn doNode_generate_landscape_from_image(self: *Simulator) void {
        cpp_nodes.generate_landscape_from_image(&self.grid, "content/tides_2.0.png");
    }
};

pub const SimulatorProgress = struct {
    percent: f32 = 0,
};
