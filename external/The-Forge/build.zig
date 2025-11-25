const std = @import("std");

const tides_renderer_base_path = "external/The-Forge/Examples_3/TidesRenderer";
const debug_path = "/PC Visual Studio 2019/x64/DebugNoValidation";
const debug_config = "/p:Configuration=DebugNoValidation";
const release_path = "/PC Visual Studio 2019/x64/Release";
const release_config = "/p:Configuration=Release";
var path_buf: [256]u8 = undefined;
var config_buf: [256]u8 = undefined;
var tides_renderer_output_path: []const u8 = undefined;
var config: []const u8 = undefined;

pub const Package = struct {
    zforge: *std.Build.Module,
    zforge_cpp: *std.Build.Step.Compile,

    pub fn link(pkg: Package, b: *std.Build, exe: *std.Build.Step.Compile) void {
        exe.root_module.addImport("zforge", pkg.zforge);
        exe.linkLibrary(pkg.zforge_cpp);

        exe.linkLibC();
        exe.addLibraryPath(b.path(tides_renderer_output_path));
    }
};

pub fn package(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
    _: struct {},
) Package {
    const zforge = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("external/The-Forge/main.zig"),
    });

    var zforge_cpp = b.addStaticLibrary(.{
        .name = "zforge",
        .target = target,
        .optimize = optimize,
    });

    if (optimize == .Debug) {
        tides_renderer_output_path = std.fmt.bufPrintZ(&path_buf, "{s}{s}", .{ tides_renderer_base_path, debug_path }) catch unreachable;
        config = debug_config;
    } else {
        tides_renderer_output_path = std.fmt.bufPrintZ(&path_buf, "{s}{s}", .{ tides_renderer_base_path, release_path }) catch unreachable;
        config = release_config;
    }

    zforge_cpp.root_module.addCMacro("_MT", "1");
    zforge_cpp.root_module.addCMacro("_DLL", "1");

    // zforge_cpp.linkage = .dynamic;
    zforge_cpp.linkLibC();
    // zforge_cpp.linkLibCpp();
    zforge_cpp.addIncludePath(b.path("external/The-Forge/Common_3/Application/Interfaces"));
    zforge_cpp.addIncludePath(b.path("external/The-Forge/Common_3/Graphics/Interfaces"));
    zforge_cpp.addIncludePath(b.path("external/The-Forge/Common_3/Resources/ResourceLoader/Interfaces"));
    zforge_cpp.addIncludePath(b.path("external/The-Forge/Common_3/Utilities/Interfaces"));
    zforge_cpp.addIncludePath(b.path("Common_3/Utilities/Log"));
    zforge_cpp.addCSourceFiles(.{
        .files = &.{
            "external/The-Forge/Common_3/Application/Interfaces/IFont_glue.cpp",
            "external/The-Forge/Common_3/Graphics/Interfaces/IGraphics_glue.cpp",
            "external/The-Forge/Common_3/Resources/ResourceLoader/Interfaces/IResourceLoader_glue.cpp",
            "external/The-Forge/Common_3/Utilities/Interfaces/IFileSystem_glue.cpp",
            "external/The-Forge/Common_3/Utilities/Interfaces/IMemory_glue.cpp",
            "external/The-Forge/Common_3/Utilities/Log/Log_glue.cpp",
        },
        .flags = &.{
            "-DTIDES",
            "-DNO_TIDES_FORGE_DEBUG",
            // "-MD",
        },
    });

    const tides_renderer_build_step = buildTheForgeRenderer(b);
    const tides_the_forge_base_path = "external/The-Forge";
    const d3d_agility_sdk_path = tides_the_forge_base_path ++ "/Common_3/Graphics/ThirdParty/OpenSource/Direct3d12Agility/bin/x64";
    // TODO(gmodarelli): Check if OS is windows and if target is debug
    zforge_cpp.addLibraryPath(b.path(tides_renderer_base_path));
    zforge_cpp.addLibraryPath(b.path(tides_renderer_output_path));
    zforge_cpp.linkSystemLibrary("dxguid");
    zforge_cpp.linkSystemLibrary("ole32");
    zforge_cpp.linkSystemLibrary("oleaut32");
    zforge_cpp.linkSystemLibrary("OS");
    zforge_cpp.linkSystemLibrary("Renderer");
    zforge_cpp.linkSystemLibrary("ws2_32");
    zforge_cpp.linkSystemLibrary("Xinput9_1_0");
    zforge_cpp.step.dependOn(tides_renderer_build_step);

    // Install DLLs
    var file_buf: [256]u8 = undefined;
    var file_path: []const u8 = undefined;
    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ tides_renderer_output_path, "WinPixEventRunTime.dll" }) catch unreachable;
    var install_file = b.addInstallFile(b.path(file_path), "bin/WinPixEventRunTime.dll");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ tides_renderer_output_path, "amd_ags_x64.dll" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/amd_ags_x64.dll");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ tides_renderer_output_path, "dxcompiler.dll" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/dxcompiler.dll");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ d3d_agility_sdk_path, "D3D12Core.dll" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/d3d12/D3D12Core.dll");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ d3d_agility_sdk_path, "D3D12SDKLayers.dll" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/d3d12/D3D12SDKLayers.dll");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ d3d_agility_sdk_path, "D3D12Core.pdb" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/d3d12/D3D12Core.pdb");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ d3d_agility_sdk_path, "D3D12SDKLayers.pdb" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/d3d12/D3D12SDKLayers.pdb");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    // Install Configuration Files
    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ tides_renderer_base_path, "src/GPUCfg/gpu.cfg" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/GPUCfg/gpu.cfg");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ tides_the_forge_base_path, "Common_3/OS/Windows/pc_gpu.data" }) catch unreachable;
    install_file = b.addInstallFile(b.path(file_path), "bin/gpu.data");
    install_file.step.dependOn(tides_renderer_build_step);
    zforge_cpp.step.dependOn(&install_file.step);

    return .{
        .zforge = zforge,
        .zforge_cpp = zforge_cpp,
    };
}

// fn installFile(b: *std.Build, tides_renderer_build_step: *std.Step, zforge_cpp: *std.Build.Step.Compile, src_folder: []const u8, file: []const u8) void {
//     var bin_buf: [256]u8 = undefined;
//     var file_buf: [256]u8 = undefined;
//     var bin_path: []const u8 = undefined;
//     var file_path: []const u8 = undefined;
//     bin_path = std.fmt.bufPrintZ(&bin_buf, "bin/{s}", .{file}) catch unreachable;
//     file_path = std.fmt.bufPrintZ(&file_buf, "{s}/{s}", .{ src_folder, file }) catch unreachable;

//     var install_file = b.addInstallFile(b.path(file_path), bin_path);
//     install_file.step.dependOn(tides_renderer_build_step);
//     zforge_cpp.step.dependOn(&install_file.step);
// }

pub fn build(_: *std.Build) void {}

fn buildTheForgeRenderer(b: *std.Build) *std.Build.Step {
    const build_step = b.step(
        "the-forge-tides-renderer",
        "Build The-Forge renderer",
    );

    const solution_path = thisDir() ++ "/Examples_3/TidesRenderer/PC Visual Studio 2019/TidesRenderer.sln";
    const command = [_][]const u8{
        "./tools/external/msvc_BuildTools/MSBuild/Current/Bin/amd64/MSBuild",
        config,
        solution_path,
    };

    build_step.dependOn(&b.addSystemCommand(&command).step);
    return build_step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
