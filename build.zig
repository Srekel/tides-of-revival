const std = @import("std");
const Builder = std.build.Builder;

const flecs = @import("external/zig-flecs/build.zig");
const zaudio = @import("external/zig-gamedev/libs/zaudio/build.zig");
const zbullet = @import("external/zig-gamedev/libs/zbullet/build.zig");
const zglfw = @import("external/zig-gamedev/libs/zglfw/build.zig");
const zwin32 = @import("external/zig-gamedev/libs/zwin32/build.zig");
const zd3d12 = @import("external/zig-gamedev/libs/zd3d12/build.zig");
const zpix = @import("external/zig-gamedev/libs/zpix/build.zig");
const zmath = @import("external/zig-gamedev/libs/zmath/build.zig");
const zmesh = @import("external/zig-gamedev/libs/zmesh/build.zig");
const znoise = @import("external/zig-gamedev/libs/znoise/build.zig");
const zpool = @import("external/zig-gamedev/libs/zpool/build.zig");
const zstbi = @import("external/zig-gamedev/libs/zstbi/build.zig");
const ztracy = @import("external/zig-gamedev/libs/ztracy/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "TidesOfRevival",
        .root_source_file = .{ .path = thisDir() ++ "/src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.install();

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

    const zaudio_pkg = zaudio.package(b, target, optimize, .{});

    const zbullet_pkg = zbullet.package(b, target, optimize, .{});

    const zglfw_pkg = zglfw.package(b, target, optimize, .{});

    const zmath_pkg = zmath.package(b, target, optimize, .{
        .options = .{ .enable_cross_platform_determinism = false },
    });
    const zmesh_options = zmesh.Options{ .shape_use_32bit_indices = true };
    const zmesh_pkg = zmesh.package(b, target, optimize, .{ .options = zmesh_options });

    const znoise_pkg = znoise.package(b, target, optimize, .{});

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
        .source_dir = thisDir() ++ "/src/shaders/compiled",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/shaders",
    });
    install_shaders_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_shaders_step.step);

    const install_meshes_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/content/meshes",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/meshes",
    });
    install_meshes_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_meshes_step.step);

    const install_patches_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/content/patch",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/patch",
    });
    install_patches_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_patches_step.step);

    const install_textures_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/content/textures",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/content/textures",
    });
    install_textures_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_textures_step.step);

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;

    const zig_flecs_pkg = flecs.Package.build(b, target, optimize, .{});

    exe.addModule("flecs", zig_flecs_pkg.flecs);
    exe.addModule("zaudio", zaudio_pkg.zaudio);
    exe.addModule("zbullet", zbullet_pkg.zbullet);
    exe.addModule("zglfw", zglfw_pkg.zglfw);
    exe.addModule("zmath", zmath_pkg.zmath);
    exe.addModule("zmesh", zmesh_pkg.zmesh);
    exe.addModule("znoise", znoise_pkg.znoise);
    exe.addModule("zpool", zpool_pkg.zpool);
    exe.addModule("zstbi", zstbi_pkg.zstbi);
    exe.addModule("ztracy", ztracy_pkg.ztracy);

    zig_flecs_pkg.link(exe);
    zaudio_pkg.link(exe);
    zbullet_pkg.link(exe);
    zwin32_pkg.link(exe, .{ .d3d12 = true });
    zd3d12_pkg.link(exe);
    zpix_pkg.link(exe);
    zglfw_pkg.link(exe);
    zmesh_pkg.link(exe);
    znoise_pkg.link(exe);
    zstbi_pkg.link(exe);
    ztracy_pkg.link(exe);

    exe.install();

    const run_cmd = exe.run();
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn buildShaders(b: *std.build.Builder) *std.build.Step {
    const dxc_step = b.step(
        "tides-of-revival-dxc",
        "Build shaders",
    );

    var dxc_command = makeDxcCmd("src/shaders/instanced.hlsl", "vsInstanced", "instanced.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/instanced.hlsl", "psInstanced", "instanced.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/terrain_quad_tree.hlsl", "vsTerrainQuadTree", "terrain_quad_tree.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/terrain_quad_tree.hlsl", "psTerrainQuadTree", "terrain_quad_tree.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/sample_env_texture.hlsl", "vsSampleEnvTexture", "sample_env_texture.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/sample_env_texture.hlsl", "psSampleEnvTexture", "sample_env_texture.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/deferred_lighting.hlsl", "csDeferredLighting", "deferred_lighting.cs.cso", "cs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/lighting_composition.hlsl", "csLightingComposition", "lighting_composition.cs.cso", "cs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);

    dxc_command = makeDxcCmd("src/shaders/generate_brdf_integration.hlsl", "csGenerateBrdfIntegrationTexture", "generate_brdf_integration_texture.cs.cso", "cs", "");
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
