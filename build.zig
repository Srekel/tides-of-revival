const std = @import("std");
const Builder = std.build.Builder;

const flecs = @import("external/zig-flecs/build.zig");
// const glfw = @import("external/zig-gamedev/libs/mach-glfw/build.zig");
const zaudio = @import("external/zig-gamedev/libs/zaudio/build.zig");
const zbullet = @import("external/zig-gamedev/libs/zbullet/build.zig");
const zglfw = @import("external/zig-gamedev/libs/zglfw/build.zig");
const zwin32 = @import("external/zig-gamedev/libs/zwin32/build.zig");
const zd3d12 = @import("external/zig-gamedev/libs/zd3d12/build.zig");
const zmath = @import("external/zig-gamedev/libs/zmath/build.zig");
const zmesh = @import("external/zig-gamedev/libs/zmesh/build.zig");
const znoise = @import("external/zig-gamedev/libs/znoise/build.zig");
const zpool = @import("external/zig-gamedev/libs/zpool/build.zig");
const ztracy = @import("external/zig-gamedev/libs/ztracy/build.zig");

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("ElvengroinLegacy", "src/main.zig");

    exe.setTarget(b.standardTargetOptions(.{}));
    exe.setBuildMode(b.standardReleaseOptions());

    exe.addPackagePath("zigimg", "external/zigimg/zigimg.zig");
    // exe.addPackagePath("qoi", "external/zig-qoi/src/qoi.zig");
    exe.addPackagePath("args", "external/zig-args/args.zig");

    const zmesh_options = zmesh.BuildOptionsStep.init(b, .{});
    const zmesh_pkg = zmesh.getPkg(&.{zmesh_options.getPkg()});

    const ztracy_enable = b.option(bool, "ztracy-enable", "Enable Tracy profiler") orelse false;
    const ztracy_options = ztracy.BuildOptionsStep.init(b, .{ .enable_ztracy = ztracy_enable });
    const ztracy_pkg = ztracy.getPkg(&.{ztracy_options.getPkg()});

    const zd3d12_enable_debug_layer = b.option(bool, "zd3d12-enable_debug_layer", "Enable D3D12 Debug Layer") orelse false;
    const zd3d12_enable_gbv = b.option(bool, "zd3d12-enable_gbv", "Enable D3D12 GPU Based Validation") orelse false;
    const zd3d12_options = zd3d12.BuildOptionsStep.init(b, .{
        .enable_debug_layer = zd3d12_enable_debug_layer,
        .enable_gbv = zd3d12_enable_gbv,
        .enable_d2d = true,
        .upload_heap_capacity = 256 * 1024 * 1024,
    });
    const zd3d12_pkg = zd3d12.getPkg(&.{ zwin32.pkg, zd3d12_options.getPkg() });

    const dxc_step = buildShaders(b);
    const install_content_step = b.addInstallDirectory(.{
        .source_dir = thisDir() ++ "/src/shaders/compiled",
        .install_dir = .{ .custom = "" },
        .install_subdir = "bin/shaders",
    });
    install_content_step.step.dependOn(dxc_step);
    exe.step.dependOn(&install_content_step.step);

    // This is needed to export symbols from an .exe file.
    // We export D3D12SDKVersion and D3D12SDKPath symbols which
    // is required by DirectX 12 Agility SDK.
    exe.rdynamic = true;

    exe.addPackage(flecs.pkg);
    exe.addPackage(zaudio.pkg);
    exe.addPackage(zbullet.pkg);
    exe.addPackage(zglfw.pkg);
    exe.addPackage(zmesh_pkg);
    exe.addPackage(zmath.pkg);
    exe.addPackage(znoise.pkg);
    exe.addPackage(zpool.pkg);
    exe.addPackage(ztracy_pkg);
    exe.addPackage(zd3d12_pkg);
    exe.addPackage(zwin32.pkg);

    flecs.link(exe, exe.target);
    zaudio.link(exe);
    zbullet.link(exe);
    zglfw.link(exe);
    zmesh.link(exe, zmesh_options);
    znoise.link(exe);
    ztracy.link(exe, ztracy_options);
    zd3d12.link(exe, zd3d12_options);

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
        "elvengroin-legacy-dxc",
        "Build shaders",
    );

    var dxc_command = makeDxcCmd("src/shaders/basic_pbr.hlsl", "vsMain", "basic_pbr.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/basic_pbr.hlsl", "vsInstancedMesh", "basic_pbr_instanced.vs.cso", "vs", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/basic_pbr.hlsl", "psTerrain", "basic_pbr_terrain.ps.cso", "ps", "");
    dxc_step.dependOn(&b.addSystemCommand(&dxc_command).step);
    dxc_command = makeDxcCmd("src/shaders/basic_pbr.hlsl", "psProceduralMesh", "basic_pbr_mesh.ps.cso", "ps", "");
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
