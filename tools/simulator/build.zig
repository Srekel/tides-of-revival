const std = @import("std");
const Builder = std.build.Builder;

pub fn buildExe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
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

    exe.addCSourceFiles(.{
        .files = &.{"src/single_header_wrapper.cpp"},
        .flags = &.{
            "-g",
            "-O0",
            "-DJCV_DISABLE_STRUCT_PACKING", // https://github.com/ziglang/zig/issues/20405
        },
    });

    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(b.path("src/ui"));
    exe.addIncludePath(b.path("src/sim"));
    exe.addIncludePath(b.path("src/sim_cpp"));
    exe.addIncludePath(b.path("../../external/voronoi/src"));

    ///////////
    // MODULES

    exe.root_module.addImport("args", b.createModule(.{
        .root_source_file = b.path("../../external/zig-args/args.zig"),
        .imports = &.{},
    }));

    // ZIG GAMEDEV
    // zjobs
    const zjobs = b.dependency("zjobs", .{});
    exe.root_module.addImport("zjobs", zjobs.module("root"));

    // // zmath
    const zmath = b.dependency("zmath", .{
        .target = target,
        .optimize = optimize,
        .enable_cross_platform_determinism = false,
    });
    exe.root_module.addImport("zmath", zmath.module("root"));

    // znoise
    const znoise = b.dependency("znoise", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("znoise", znoise.module("root"));
    exe.linkLibrary(znoise.artifact("FastNoiseLite"));

    // zstbi
    const zstbi = b.dependency("zstbi", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zstbi", zstbi.module("root"));
    exe.linkLibrary(zstbi.artifact("zstbi"));

    // END MODULES
    //////////////

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn buildCppNodesDll(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const dll_cpp_nodes = b.addSharedLibrary(.{
        .name = "CppNodes",
        .target = target,
        .optimize = optimize,
    });

    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    dll_cpp_nodes.linkLibC();
    if (abi != .msvc) {
        dll_cpp_nodes.linkLibCpp();
    }

    dll_cpp_nodes.addIncludePath(b.path("src/sim_cpp"));

    dll_cpp_nodes.addCSourceFiles(.{
        .files = &.{"src/sim_cpp/world_generator.cpp"},
        .flags = &.{
            "-g",
            "-O0",
            "-DJCV_DISABLE_STRUCT_PACKING", // https://github.com/ziglang/zig/issues/20405
        },
    });

    // Single header libraries
    dll_cpp_nodes.addIncludePath(b.path("../../external/FastNoiseLite/C"));
    dll_cpp_nodes.addIncludePath(b.path("../../external/poisson-disk-sampling/include"));
    dll_cpp_nodes.addIncludePath(b.path("../../external/voronoi/src"));
    dll_cpp_nodes.addIncludePath(b.path("../../external/stb"));

    b.installArtifact(dll_cpp_nodes);
}

pub fn buildUIDll(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const dll_ui = b.addSharedLibrary(.{
        .name = "UI",
        .target = target,
        .optimize = optimize,
    });

    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    dll_ui.linkLibC();
    if (abi != .msvc) {
        dll_ui.linkLibCpp();
    }

    dll_ui.addIncludePath(b.path("src"));
    dll_ui.addIncludePath(b.path("src/ui"));
    dll_ui.addIncludePath(b.path("src/sim_cpp"));
    dll_ui.addIncludePath(b.path("../../external/imgui"));
    dll_ui.addIncludePath(b.path("../../external/imgui/backends/"));

    dll_ui.addCSourceFiles(.{
        .files = &.{
            "src/ui/main.cpp",
            "src/ui/d3d11/d3d11.cpp",
        },
        .flags = &.{"-DZIG_BUILD"},
    });

    dll_ui.addCSourceFiles(.{
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

    dll_ui.linkSystemLibrary("d3d11");
    dll_ui.linkSystemLibrary("d3dcompiler_47");
    dll_ui.linkSystemLibrary("Gdi32");
    dll_ui.linkSystemLibrary("Dwmapi");

    // Install shaders
    var shader_remap = b.addInstallFile(b.path("src/ui/d3d11/shaders/Remap.hlsl"), "bin/shaders/Remap.hlsl");
    dll_ui.step.dependOn(&shader_remap.step);
    var shader_square = b.addInstallFile(b.path("src/ui/d3d11/shaders/Square.hlsl"), "bin/shaders/Square.hlsl");
    dll_ui.step.dependOn(&shader_square.step);

    // Link in our cpp library of nodes
    b.installArtifact(dll_ui);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    buildExe(b, target, optimize);
    buildCppNodesDll(b, target, optimize);
    buildUIDll(b, target, optimize);

    // dll.addCSourceFiles(.{
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
