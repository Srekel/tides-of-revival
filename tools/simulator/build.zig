const std = @import("std");
const Builder = std.build.Builder;

pub fn buildCppNodesDll(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const dll = b.addSharedLibrary(.{
        .name = "CppNodes",
        .target = target,
        .optimize = optimize,
    });

    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    dll.linkLibC();
    if (abi != .msvc) {
        dll.linkLibCpp();
    }

    dll.addIncludePath(b.path("src/sim_cpp"));

    dll.addCSourceFiles(.{
        .files = &.{"src/sim_cpp/world_generator.cpp"},
        .flags = &.{""},
    });

    // Single header libraries
    dll.addIncludePath(b.path("../../external/FastNoiseLite/C"));
    dll.addIncludePath(b.path("../../external/poisson-disk-sampling/include"));
    dll.addIncludePath(b.path("../../external/voronoi/src"));
    dll.addIncludePath(b.path("../../external/stb"));

    // dll.linkSystemLibrary("Gdi32");
    // dll.linkSystemLibrary("Dwmapi");

    b.installArtifact(dll);

    const install_file = b.addInstallFile(b.path("lib/CppNodes.lib"), "bin/CppNodes.lib");
    install_file.step.dependOn(&dll.step);
    // const run_cmd = b.addRunArtifact(dll);
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }

    // const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_cmd.step);
    return dll;
}

pub fn buildExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, cpp_nodes: *std.Build.Step.Compile) void {
    const exe = b.addExecutable(.{
        .name = "Simulator",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    exe.linkLibC();
    if (abi != .msvc) {
        exe.linkLibCpp();
    }

    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(b.path("src/sim_cpp"));
    exe.addIncludePath(b.path("../../external/imgui"));
    exe.addIncludePath(b.path("../../external/imgui/backends/"));

    exe.addCSourceFiles(.{
        .files = &.{"src/ui/main.cpp"},
        .flags = &.{"-DZIG_BUILD"},
    });

    exe.addCSourceFiles(.{
        .files = &.{
            "../../external/imgui/imgui.cpp",
            "../../external/imgui/imgui_draw.cpp",
            "../../external/imgui/imgui_tables.cpp",
            "../../external/imgui/imgui_widgets.cpp",
            "../../external/imgui/backends/imgui_impl_dx11.cpp",
            "../../external/imgui/backends/imgui_impl_win32.cpp",
        },
        .flags = &.{""},
    });

    exe.root_module.addImport("args", b.createModule(.{
        .root_source_file = b.path("../../external/zig-args/args.zig"),
        .imports = &.{},
    }));

    exe.linkSystemLibrary("d3d11");
    exe.linkSystemLibrary("d3dcompiler_47");
    exe.linkSystemLibrary("Gdi32");
    exe.linkSystemLibrary("Dwmapi");

    // Link in our cpp library of nodes
    exe.step.dependOn(&cpp_nodes.step);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const cpp_nodes = buildCppNodesDll(b, target, optimize);
    buildExe(b, target, optimize, cpp_nodes);

    // exe.addCSourceFiles(.{
    //     .files = &.{"src/single_header_wrapper.cpp"},
    //     .flags = &.{},
    // });

    // ███╗   ███╗ ██████╗ ██████╗ ██╗   ██╗██╗     ███████╗███████╗
    // ████╗ ████║██╔═══██╗██╔══██╗██║   ██║██║     ██╔════╝██╔════╝
    // ██╔████╔██║██║   ██║██║  ██║██║   ██║██║     █████╗  ███████╗
    // ██║╚██╔╝██║██║   ██║██║  ██║██║   ██║██║     ██╔══╝  ╚════██║
    // ██║ ╚═╝ ██║╚██████╔╝██████╔╝╚██████╔╝███████╗███████╗███████║
    // ╚═╝     ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚══════╝

    // // zigimg
    // exe.root_module.addImport("zigimg", b.createModule(.{
    //     .root_source_file = b.path("../../external/zigimg/zigimg.zig"),
    //     .imports = &.{},
    // }));

    // // ZIG GAMEDEV
    // // zmath
    // const zmath = b.dependency("zmath", .{
    //     .target = target,
    //     .optimize = optimize,
    //     .enable_cross_platform_determinism = false,
    // });
    // exe.root_module.addImport("zmath", zmath.module("root"));

    // // znoise
    // const znoise = b.dependency("znoise", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.root_module.addImport("znoise", znoise.module("root"));
    // exe.linkLibrary(znoise.artifact("FastNoiseLite"));

    // // zpool
    // const zpool = b.dependency("zpool", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.root_module.addImport("zpool", zpool.module("root"));

    // // zstbi
    // const zstbi = b.dependency("zstbi", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // exe.root_module.addImport("zstbi", zstbi.module("root"));
    // exe.linkLibrary(zstbi.artifact("zstbi"));

    // // zwin32
    // const zwin32 = b.dependency("zwin32", .{
    //     .target = target,
    //     .optimize = optimize,
    // });
    // _ = zwin32; // autofix

    // Recast
    // const zignav = b.dependency("zignav", .{});
    // exe.root_module.addImport("zignav", zignav.module("zignav"));
    // exe.linkLibrary(zignav.artifact("zignav_c_cpp"));

    // const install_fonts_step = b.addInstallDirectory(.{
    //     .source_dir = b.path("content/fonts"),
    //     .install_dir = .{ .custom = "" },
    //     .install_subdir = "bin/content/fonts",
    // });
    // exe.step.dependOn(&install_fonts_step.step);

    // @import("zwin32").install_d3d12(&exe.step, .bin);
    // @import("system_sdk").addLibraryPathsTo(exe);

}
