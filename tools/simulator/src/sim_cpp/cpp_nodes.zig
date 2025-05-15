const std = @import("std");

const c_cpp_nodes = @cImport({
    @cInclude("world_generator.h");
});

pub const fn_generate_voronoi_map = *const fn (
    map_settings: *const c_cpp_nodes.MapSettings,
    voronoi_settings: *const c_cpp_nodes.VoronoiSettings,
    grid: *c_cpp_nodes.Voronoi,
) callconv(.C) void;
pub const fn_generate_landscape_from_image = *const fn (
    grid: *c_cpp_nodes.Voronoi,
    image_path: [*:0]const u8,
) callconv(.C) void;
// const fn_generate_landscape = *const fn (map_settings: *const c_cpp_nodes.MapSettings, grid: *c_cpp_nodes.Voronoi) callconv(.C) void;
pub const fn_generate_landscape_preview = *const fn (
    grid: *c_cpp_nodes.Voronoi,
    image_width: c_uint,
    image_height: c_uint,
) callconv(.C) [*c]u8;
pub const fn_voronoi_to_imagef32 = *const fn (
    grid: *c_cpp_nodes.Voronoi,
    image_width: c_uint,
    image_height: c_uint,
) callconv(.C) [*c]f32;

pub var generate_landscape_from_image: fn_generate_landscape_from_image = undefined;
pub var generate_landscape_preview: fn_generate_landscape_preview = undefined;
pub var voronoi_to_imagef32: fn_voronoi_to_imagef32 = undefined;

var dll_cpp_nodes: std.DynLib = undefined;
pub fn init() void {
    dll_cpp_nodes = std.DynLib.open("CppNodes.dll") catch unreachable;
    generate_landscape_from_image = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_landscape_from_image, "generate_landscape_from_image").?.?;
    generate_landscape_preview = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_generate_landscape_preview, "generate_landscape_preview").?.?;
    voronoi_to_imagef32 = dll_cpp_nodes.lookup(c_cpp_nodes.PFN_voronoi_to_imagef32, "voronoi_to_imagef32").?.?;
}

pub fn deinit() void {
    dll_cpp_nodes.close();
}
