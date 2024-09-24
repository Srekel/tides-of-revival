const std = @import("std");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

const fn_generate_voronoi_map = *const fn (map_settings: *const c_cpp_nodes.map_settings_t, grid: *c_cpp_nodes.grid_t) callconv(.C) void;
const fn_generate_landscape_from_image = *const fn (map_settings: *const c_cpp_nodes.map_settings_t, grid: *c_cpp_nodes.grid_t, image_path: [*:0]const u8) callconv(.C) void;
// const fn_generate_landscape = *const fn (map_settings: *const c_cpp_nodes.map_settings_t, grid: *c_cpp_nodes.grid_t) callconv(.C) void;
const fn_generate_landscape_preview = *const fn (grid: *c_cpp_nodes.grid_t, image_width: c_uint, image_height: c_uint) callconv(.C) [*c]u8;

pub const Simulator = struct {
    generate_voronoi_map: fn_generate_voronoi_map = undefined,
    generate_landscape_from_image: fn_generate_landscape_from_image = undefined,
    generate_landscape_preview: fn_generate_landscape_preview = undefined,

    grid: c_cpp_nodes.grid_t = undefined,
    map_settings: c_cpp_nodes.map_settings_t = undefined,

    pub fn init(self: *Simulator) void {
        var dll_cpp_nodes = std.DynLib.open("CppNodes.dll") catch unreachable;
        self.generate_voronoi_map = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_voronoi_map, "generate_voronoi_map").?.?;
        self.generate_landscape_from_image = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_landscape_from_image, "generate_landscape_from_image").?.?;
        self.generate_landscape_preview = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_landscape_preview, "generate_landscape_preview").?.?;

        self.map_settings.size = 8.0;
        self.map_settings.radius = 0.05;
        self.map_settings.num_relaxations = 10;
        self.map_settings.seed = 1981;
        self.map_settings.landscape_seed = 12421;
        self.map_settings.landscape_frequency = 1.0;
        self.map_settings.landscape_octaves = 8;
    }

    pub fn simulate(self: *Simulator) void {
        std.debug.print("simulate \n{any}\n\n", .{self.map_settings});
        self.generate_voronoi_map(&self.map_settings, &self.grid);
        self.generate_landscape_from_image(&self.map_settings, &self.grid, "content/tides_2.0.png");
        // std.debug.print("LOOOL {any}\n\n", .{self.grid.voronoi_grid.?.*.numsites});
    }

    pub fn get_preview(self: *Simulator, image_width: u32, image_height: u32) [*c]u8 {
        return self.generate_landscape_preview(&self.grid, image_width, image_height);
    }
};
