const std = @import("std");
const Builder = std.build.Builder;

const zd3d12 = @import("external/zig-gamedev/libs/zd3d12/build.zig");
const zflecs = @import("external/zig-gamedev/libs/zflecs/build.zig");
const zglfw = @import("external/zig-gamedev/libs/zglfw/build.zig");
const zmath = @import("external/zig-gamedev/libs/zmath/build.zig");
const zmesh = @import("external/zig-gamedev/libs/zmesh/build.zig");
const znoise = @import("external/zig-gamedev/libs/znoise/build.zig");
const zphysics = @import("external/zig-gamedev/libs/zphysics/build.zig");
const zpix = @import("external/zig-gamedev/libs/zpix/build.zig");
const zpool = @import("external/zig-gamedev/libs/zpool/build.zig");
const zstbi = @import("external/zig-gamedev/libs/zstbi/build.zig");
const ztracy = @import("external/zig-gamedev/libs/ztracy/build.zig");
const zwin32 = @import("external/zig-gamedev/libs/zwin32/build.zig");

const wwise_zig = @import("external/wwise-zig/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "TidesOfRevival",
        .root_source_file = .{ .path = thisDir() ++ "/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    _ = b.option([]const u8, "build_date", "date of the build");
    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "build_date", "2023-11-25");

    exe.addModule("websocket", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/external/websocket.zig/src/websocket.zig" },
        .dependencies = &.{},
    }));
    exe.addModule("zigimg", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/external/zigimg/zigimg.zig" },
        .dependencies = &.{},
    }));
    exe.addModule("args", b.createModule(.{
        .source_file = .{ .path = thisDir() ++ "/external/zig-args/args.zig" },
        .dependencies = &.{},
    }));

    const abi = (std.zig.system.NativeTargetInfo.detect(target) catch unreachable).target.abi;
    exe.linkLibC();
    if (abi != .msvc)
        exe.linkLibCpp();

    // Building and Linking Tides Renderer
    {
        const build_step = buildTheForgeRenderer(b);

        const tides_renderer_base_path = thisDir() ++ "/external/The-Forge/Examples_3/TidesRenderer";
        // TODO(gmodarelli): Check if OS is windows and if target is debug
        const tides_renderer_output_path = tides_renderer_base_path ++ "/PC Visual Studio 2019/x64/Debug";

        exe.addLibraryPath(.{ .path = tides_renderer_output_path });
        exe.linkSystemLibrary("TidesRenderer");
        exe.step.dependOn(build_step);

        // Install DLLs
        var install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/TidesRenderer.dll" }, "bin/TidesRenderer.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/TidesRenderer.pdb" }, "bin/TidesRenderer.pdb");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/WinPixEventRunTime.dll" }, "bin/WinPixEventRunTime.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/amd_ags_x64.dll" }, "bin/amd_ags_x64.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/dxcompiler.dll" }, "bin/dxcompiler.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/VkLayer_khronos_validation.dll" }, "bin/VkLayer_khronos_validation.dll");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);

        // Install Configuration Files
        install_file = b.addInstallFile(.{ .path = tides_renderer_base_path ++ "/src/GPUCfg/gpu.cfg" }, "bin/GPUCfg/gpu.cfg");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_base_path ++ "/src/GPUCfg/gpu.data" }, "bin/GPUCfg/gpu.data");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);
        install_file = b.addInstallFile(.{ .path = tides_renderer_output_path ++ "/VkLayer_khronos_validation.json" }, "bin/VkLayer_khronos_validation.json");
        install_file.step.dependOn(build_step);
        exe.step.dependOn(&install_file.step);

        // Install Content
        var install_content_step = b.addInstallDirectory(.{
            .source_dir = .{ .path = tides_renderer_output_path ++ "/content/compiled_shaders" },
            .install_dir = .{ .custom = "" },
            .install_subdir = "bin/content/compiled_shaders",
        });
        install_content_step.step.dependOn(build_step);
        exe.step.dependOn(&install_content_step.step);

        install_content_step = b.addInstallDirectory(.{
            .source_dir = .{ .path = tides_renderer_base_path ++ "/resources/textures/default" },
            .install_dir = .{ .custom = "" },
            .install_subdir = "bin/content/textures/default",
        });
        install_content_step.step.dependOn(build_step);
        exe.step.dependOn(&install_content_step.step);
    }

    const zflecs_pkg = zflecs.package(b, target, optimize, .{});

    const zglfw_pkg = zglfw.package(b, target, optimize, .{});

    const zmath_pkg = zmath.package(b, target, optimize, .{
        .options = .{ .enable_cross_platform_determinism = false },
    });

    const zmesh_options = zmesh.Options{ .shape_use_32bit_indices = true };
    const zmesh_pkg = zmesh.package(b, target, optimize, .{ .options = zmesh_options });

    const znoise_pkg = znoise.package(b, target, optimize, .{});

    const zphysics_options = zphysics.Options{
        .use_double_precision = false,
        .enable_cross_platform_determinism = false,
    };
    const zphysics_pkg = zphysics.package(b, target, optimize, .{ .options = zphysics_options });

    const zpool_pkg = zpool.package(b, target, optimize, .{});

    const zstbi_pkg = zstbi.package(b, target, optimize, .{});

    const ztracy_enable = b.option(bool, "ztracy-enable", "Enable Tracy profiler") orelse false;
    const ztracy_options = ztracy.Options{ .enable_ztracy = ztracy_enable };
    const ztracy_pkg = ztracy.package(b, target, optimize, .{ .options = ztracy_options });

    const zwin32_pkg = zwin32.package(b, target, optimize, .{});
    const zpix_enable = b.option(bool, "zpix-enable", "Enable PIX for Windows profiler") orelse false;
    const zpix_pkg = zpix.package(b, target, optimize, .{
        .options = .{ .enable = zpix_enable },
        .deps = .{ .zwin32 = zwin32_pkg.zwin32 },
    });

    const install_fonts_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/fonts" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/fonts",
    });
    exe.step.dependOn(&install_fonts_step.step);

    const install_systems_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/systems" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/systems",
    });
    exe.step.dependOn(&install_systems_step.step);

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;

    exe.addModule("zflecs", zflecs_pkg.zflecs);
    exe.addModule("zglfw", zglfw_pkg.zglfw);
    exe.addModule("zmath", zmath_pkg.zmath);
    exe.addModule("zmesh", zmesh_pkg.zmesh);
    exe.addModule("znoise", znoise_pkg.znoise);
    exe.addModule("zpool", zpool_pkg.zpool);
    exe.addModule("zstbi", zstbi_pkg.zstbi);
    exe.addModule("ztracy", ztracy_pkg.ztracy);

    // zd3d12_pkg.link(exe);
    zflecs_pkg.link(exe);
    zglfw_pkg.link(exe);
    zmesh_pkg.link(exe);
    znoise_pkg.link(exe);
    zphysics_pkg.link(exe);
    zpix_pkg.link(exe);
    zstbi_pkg.link(exe);
    ztracy_pkg.link(exe);
    zwin32_pkg.link(exe, .{ .d3d12 = true });

    const wwise_package = wwise_zig.package(b, target, optimize, .{
        .use_communication = true,
        .use_default_job_worker = true,
        .use_static_crt = true,
        .use_spatial_audio = false,
        .include_file_package_io_blocking = true,
        .configuration = .profile,
        .static_plugins = &.{
            "AkToneSource",
            "AkParametricEQFX",
            "AkDelayFX",
            "AkPeakLimiterFX",
            "AkRoomVerbFX",
            "AkStereoDelayFX",
            "AkSynthOneSource",
            "AkAudioInputSource",
            "AkVorbisDecoder",
        },
    }) catch unreachable;

    exe.addModule("wwise-zig", wwise_package.module);
    exe.linkLibrary(wwise_package.c_library);
    wwise_zig.wwiseLink(exe, wwise_package.options) catch unreachable;

    // const build_soundbanks_step = wwise_zig.addGenerateSoundBanksStep(
    //     b,
    //     "../tides-rpg-source-assets/tides-wwise/tides-wwise.wproj",
    //     .{
    //         .target = target,
    //     },
    // ) catch unreachable;
    // exe.step.dependOn(&build_soundbanks_step.step);

    const wwise_id_module = wwise_zig.generateWwiseIDModule(
        b,
        "content/audio/wwise/Wwise_IDs.h",
        wwise_package.module,
        .{
            // .previous_step = &build_soundbanks_step.step,
        },
    );

    exe.addModule("wwise-ids", wwise_id_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn buildTheForgeRenderer(b: *std.build.Builder) *std.build.Step {
    const build_step = b.step(
        "the-forge-tides-renderer",
        "Build The-Forge renderer",
    );

    const solution_path = thisDir() ++ "/external/The-Forge/Examples_3/TidesRenderer/PC Visual Studio 2019/TidesRenderer.sln";
    const command = [2][]const u8{
        "C:/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/amd64/MSBuild",
        solution_path,
    };

    build_step.dependOn(&b.addSystemCommand(&command).step);
    return build_step;
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
