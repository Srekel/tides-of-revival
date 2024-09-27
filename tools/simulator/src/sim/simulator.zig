const std = @import("std");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

const fn_generate_voronoi_map = *const fn (
    map_settings: *const c_cpp_nodes.MapSettings,
    voronoi_settings: *const c_cpp_nodes.VoronoiSettings,
    grid: *c_cpp_nodes.Grid,
) callconv(.C) void;
const fn_generate_landscape_from_image = *const fn (
    grid: *c_cpp_nodes.Grid,
    image_path: [*:0]const u8,
) callconv(.C) void;
// const fn_generate_landscape = *const fn (map_settings: *const c_cpp_nodes.MapSettings, grid: *c_cpp_nodes.Grid) callconv(.C) void;
const fn_generate_landscape_preview = *const fn (
    grid: *c_cpp_nodes.Grid,
    image_width: c_uint,
    image_height: c_uint,
) callconv(.C) [*c]u8;

const fn_node = *const fn (self: *Simulator) void;

pub const Simulator = struct {
    generate_voronoi_map: fn_generate_voronoi_map = undefined,
    generate_landscape_from_image: fn_generate_landscape_from_image = undefined,
    generate_landscape_preview: fn_generate_landscape_preview = undefined,

    next_nodes: std.BoundedArray(fn_node, 16) = .{},
    progress: SimulatorProgress = .{},

    grid: c_cpp_nodes.Grid = undefined,
    map_settings: c_cpp_nodes.MapSettings = undefined,
    voronoi_settings: c_cpp_nodes.VoronoiSettings = undefined,

    pub fn init(self: *Simulator) void {
        var dll_cpp_nodes = std.DynLib.open("CppNodes.dll") catch unreachable;
        self.generate_voronoi_map = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_voronoi_map, "generate_voronoi_map").?.?;
        self.generate_landscape_from_image = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_landscape_from_image, "generate_landscape_from_image").?.?;
        self.generate_landscape_preview = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_landscape_preview, "generate_landscape_preview").?.?;

        self.progress.percent = 0.2;

        self.map_settings.size = 8.0;
        self.map_settings.seed = 1981;
        self.voronoi_settings.radius = 0.05;
        self.voronoi_settings.num_relaxations = 10;

        self.next_nodes.appendAssumeCapacity(doNode_GenerateVoronoiMap1);
    }

    pub fn simulate(self: *Simulator) void {
        while (self.next_nodes.len > 0) {
            const node_function = self.next_nodes.buffer[0];
            std.log.debug("simulate \n{any}\n\n", .{node_function});
            _ = self.next_nodes.orderedRemove(0);
            node_function(self);
        }
    }

    pub fn simulateSteps(self: *Simulator, steps: u32) void {
        for (0..steps) |_| {
            if (self.next_nodes.len > 0) {
                const node_function = self.next_nodes.buffer[0];
                std.log.debug("simulate \n{any}\n\n", .{node_function});
                _ = self.next_nodes.orderedRemove(0);
                node_function(self);
            }
        }
    }

    pub fn get_preview(self: *Simulator, image_width: u32, image_height: u32) [*c]u8 {
        return self.generate_landscape_preview(&self.grid, image_width, image_height);
    }

    pub fn getProgress(self: *Simulator) SimulatorProgress {
        const progress = self.progress;
        return progress;
    }

    fn doNode_GenerateVoronoiMap1(self: *Simulator) void {
        self.generate_voronoi_map(&self.map_settings, &self.voronoi_settings, &self.grid);
        self.next_nodes.appendAssumeCapacity(doNode_generate_landscape_from_image);
    }

    fn doNode_generate_landscape_from_image(self: *Simulator) void {
        self.generate_landscape_from_image(&self.grid, "content/tides_2.0.png");
    }
};

pub const SimulatorProgress = struct {
    percent: f32 = 0,
};
