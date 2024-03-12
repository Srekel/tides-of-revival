const std = @import("std");
const Builder = std.build.Builder;

const zforge = @import("external/The-Forge/build.zig");
const zglfw = @import("external/zig-gamedev/libs/zglfw/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "TidesOfRevival",
        .root_source_file = .{ .path = thisDir() ++ "/src/zforge_main.zig" },
        .target = target,
        .optimize = optimize,
    });

    _ = b.option([]const u8, "build_date", "date of the build");
    const exe_options = b.addOptions();
    exe.root_module.addOptions("build_options", exe_options);
    const tides_renderer_base_path = thisDir() ++ "/external/The-Forge/Examples_3/TidesRenderer";
    const tides_renderer_output_path = tides_renderer_base_path ++ "/PC Visual Studio 2019/x64/Debug";
    exe.linkLibC();
    exe.addLibraryPath(.{ .path = tides_renderer_output_path });
    exe_options.addOption([]const u8, "build_date", "2023-11-25");

    const zforge_pkg = zforge.package(b, target, optimize, .{});
    const zglfw_pkg = zglfw.package(b, target, optimize, .{});

    exe.root_module.addImport("zglfw", zglfw_pkg.zglfw);

    zforge_pkg.link(exe);
    zglfw_pkg.link(exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
