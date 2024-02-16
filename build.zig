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
const wwise_zig = @import("wwise-zig");

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
    exe.root_module.addOptions("build_options", exe_options);
    exe_options.addOption([]const u8, "build_date", "2023-11-25");

    exe.root_module.addImport("websocket", b.createModule(.{
        .root_source_file = .{ .path = thisDir() ++ "/external/websocket.zig/src/websocket.zig" },
        .imports = &.{},
    }));
    exe.root_module.addImport("zigimg", b.createModule(.{
        .root_source_file = .{ .path = thisDir() ++ "/external/zigimg/zigimg.zig" },
        .imports = &.{},
    }));
    exe.root_module.addImport("args", b.createModule(.{
        .root_source_file = .{ .path = thisDir() ++ "/external/zig-args/args.zig" },
        .imports = &.{},
    }));

    // Linking ImGUI
    const abi = (std.zig.system.resolveTargetQuery(target.query) catch unreachable).abi;
    exe.linkLibC();
    if (abi != .msvc)
        exe.linkLibCpp();
    exe.linkSystemLibrary("imm32");

    exe.addIncludePath(.{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs" });
    exe.addIncludePath(.{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui" });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui/imgui.cpp" }, .flags = &.{""} });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui/imgui_widgets.cpp" }, .flags = &.{""} });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui/imgui_tables.cpp" }, .flags = &.{""} });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui/imgui_draw.cpp" }, .flags = &.{""} });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui/imgui_demo.cpp" }, .flags = &.{""} });
    exe.addCSourceFile(.{ .file = .{ .path = thisDir() ++ "/external/zig-gamedev/libs/common/libs/imgui/cimgui.cpp" }, .flags = &.{""} });

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

    const zd3d12_enable_debug_layer = b.option(bool, "zd3d12-enable_debug_layer", "Enable D3D12 Debug Layer") orelse false;
    const zd3d12_enable_gbv = b.option(bool, "zd3d12-enable_gbv", "Enable D3D12 GPU Based Validation") orelse false;
    const zd3d12_pkg = zd3d12.package(b, target, optimize, .{
        .options = .{
            .enable_debug_layer = zd3d12_enable_debug_layer,
            .enable_gbv = zd3d12_enable_gbv,
            .enable_d2d = true,
            .upload_heap_capacity = 56 * 1024 * 1024,
        },
        .deps = .{ .zwin32 = zwin32_pkg.zwin32 },
    });

    const zpix_enable = b.option(bool, "zpix-enable", "Enable PIX for Windows profiler") orelse false;
    const zpix_pkg = zpix.package(b, target, optimize, .{
        .options = .{ .enable = zpix_enable },
        .deps = .{ .zwin32 = zwin32_pkg.zwin32 },
    });

    const dxc_step = buildShaders(b);
    const install_shaders_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/src/shaders/compiled" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/shaders",
    });
    install_shaders_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_shaders_step.step);

    const install_meshes_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/meshes" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/meshes",
    });
    install_meshes_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_meshes_step.step);

    const install_prefabs_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/prefabs" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/prefabs",
    });
    install_prefabs_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_prefabs_step.step);

    // const install_patches_step = b.addInstallDirectory(.{
    //     .source_dir = thisDir() ++ "/content/patch",
    //     .install_dir = .{ .custom = "" },
    //     .install_subdir = "bin/content/patch",
    // });
    // install_patches_step.step.dependOn(dxc_step);
    // exe.step.dependOn(&install_patches_step.step);

    const install_textures_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/textures" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/textures",
    });
    install_textures_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_textures_step.step);

    const install_fonts_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/fonts" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/fonts",
    });
    install_fonts_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_fonts_step.step);

    const install_systems_step = b.addInstallDirectory(.{
        .source_dir = .{ .path = thisDir() ++ "/content/systems" },
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/systems",
    });
    install_systems_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_systems_step.step);

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;

    exe.root_module.addImport("zflecs", zflecs_pkg.zflecs);
    exe.root_module.addImport("zglfw", zglfw_pkg.zglfw);
    exe.root_module.addImport("zmath", zmath_pkg.zmath);
    exe.root_module.addImport("zmesh", zmesh_pkg.zmesh);
    exe.root_module.addImport("znoise", znoise_pkg.znoise);
    exe.root_module.addImport("zpool", zpool_pkg.zpool);
    exe.root_module.addImport("zstbi", zstbi_pkg.zstbi);
    exe.root_module.addImport("ztracy", ztracy_pkg.ztracy);

    zd3d12_pkg.link(exe);
    zflecs_pkg.link(exe);
    zglfw_pkg.link(exe);
    zmesh_pkg.link(exe);
    znoise_pkg.link(exe);
    zphysics_pkg.link(exe);
    zpix_pkg.link(exe);
    zstbi_pkg.link(exe);
    ztracy_pkg.link(exe);
    zwin32_pkg.link(exe, .{ .d3d12 = true });

    const wwise_dependency = b.dependency("wwise-zig", .{
        .target = target,
        .optimize = optimize,
        .use_communication = true,
        .use_default_job_worker = true,
        .use_spatial_audio = false,
        .use_static_crt = true,
        .include_file_package_io_blocking = true,
        .configuration = .profile,
        .static_plugins = @as([]const []const u8, &.{
            "AkToneSource",
            "AkParametricEQFX",
            "AkDelayFX",
            "AkPeakLimiterFX",
            "AkRoomVerbFX",
            "AkStereoDelayFX",
            "AkSynthOneSource",
            "AkAudioInputSource",
            "AkVorbisDecoder",
        }),
    });

    exe.root_module.addImport("wwise-zig", wwise_dependency.module("wwise-zig"));

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
        wwise_dependency.module("wwise-zig"),
        .{
            // .previous_step = &build_soundbanks_step.step,
        },
    );

    exe.root_module.addImport("wwise-ids", wwise_id_module);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn buildShaders(b: *std.Build) *std.Build.Step {
    const dxc_step = b.step(
        "tides-of-revival-dxc",
        "Build shaders",
    );

    var dxc_command = makeDxcCmd("src/shaders/tonemapping.hlsl", "vsFullscreenTriangle", "tonemapping.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/tonemapping.hlsl", "psTonemapping", "tonemapping.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/debug_visualization.hlsl", "vsFullscreenTriangle", "debug_visualization.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/debug_visualization.hlsl", "psDebugVisualization", "debug_visualization.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/downsample.hlsl", "vsFullscreenTriangle", "downsample.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/downsample.hlsl", "psDownsample", "downsample.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/upsample_blur.hlsl", "vsFullscreenTriangle", "upsample_blur.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/upsample_blur.hlsl", "psUpsampleBlur", "upsample_blur.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/gbuffer_fill.hlsl", "vsGBufferFill", "gbuffer_fill.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/gbuffer_fill.hlsl", "psGBufferFill", "gbuffer_fill_opaque.ps.cso", "ps", "PSO__OPAQUE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/gbuffer_fill.hlsl", "psGBufferFill", "gbuffer_fill_masked.ps.cso", "ps", "PSO__MASKED");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/terrain_quad_tree.hlsl", "vsTerrainQuadTree", "terrain_quad_tree.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/terrain_quad_tree.hlsl", "psTerrainQuadTree", "terrain_quad_tree.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/skybox.hlsl", "vsSkybox", "skybox.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/skybox.hlsl", "psSkybox", "skybox.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/depth_based_fog.hlsl", "vsFullscreenTriangle", "depth_based_fog.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/depth_based_fog.hlsl", "psDepthBasedFog", "depth_based_fog.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/ui.hlsl", "vsUI", "ui.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/ui.hlsl", "psUI", "ui.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/deferred_lighting.hlsl", "csDeferredLighting", "deferred_lighting.cs.cso", "cs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/generate_mipmaps.hlsl", "csGenerateMipmaps", "generate_mipmaps.cs.cso", "cs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/generate_brdf_integration.hlsl", "csGenerateBrdfIntegrationTexture", "generate_brdf_integration_texture.cs.cso", "cs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "vsGenerateEnvTexture", "generate_env_texture.vs.cso", "vs", "PSO__GENERATE_ENV_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "psGenerateEnvTexture", "generate_env_texture.ps.cso", "ps", "PSO__GENERATE_ENV_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "vsSampleEnvTexture", "sample_env_texture.vs.cso", "vs", "PSO__SAMPLE_ENV_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "psSampleEnvTexture", "sample_env_texture.ps.cso", "ps", "PSO__SAMPLE_ENV_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "vsGenerateIrradianceTexture", "generate_irradiance_texture.vs.cso", "vs", "PSO__GENERATE_IRRADIANCE_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "psGenerateIrradianceTexture", "generate_irradiance_texture.ps.cso", "ps", "PSO__GENERATE_IRRADIANCE_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "vsGeneratePrefilteredEnvTexture", "generate_prefiltered_env_texture.vs.cso", "vs", "PSO__GENERATE_PREFILTERED_ENV_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/hdri.hlsl", "psGeneratePrefilteredEnvTexture", "generate_prefiltered_env_texture.ps.cso", "ps", "PSO__GENERATE_PREFILTERED_ENV_TEXTURE");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/imgui.hlsl", "vsImGui", "imgui.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/imgui.hlsl", "psImGui", "imgui.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    return dxc_step;
}

fn makeDxcCmd(
    comptime input_path: []const u8,
    comptime entry_point: []const u8,
    comptime output_filename: []const u8,
    comptime profile: []const u8,
    comptime define: []const u8,
) [9][]const u8 {
    const shader_ver = "6_6";
    const shader_dir = thisDir() ++ "/src/shaders/compiled/";
    return [9][]const u8{
        thisDir() ++ "/external/zig-gamedev/libs/zwin32/bin/x64/dxc.exe",
        thisDir() ++ "/" ++ input_path,
        "/E " ++ entry_point,
        "/Fo " ++ shader_dir ++ output_filename,
        "/T " ++ profile ++ "_" ++ shader_ver,
        if (define.len == 0) "" else "/D " ++ define,
        "/WX",
        "/Ges",
        "/O3",
    };
}

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}
