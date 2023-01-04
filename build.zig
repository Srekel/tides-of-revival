const std = @import("std");
const Builder = std.build.Builder;

const flecs = @import("external/zig-flecs/build.zig");
// const glfw = @import("external/zig-gamedev/libs/mach-glfw/build.zig");
const zaudio = @import("external/zig-gamedev/libs/zaudio/build.zig");
const zbullet = @import("external/zig-gamedev/libs/zbullet/build.zig");
const zglfw = @import("external/zig-gamedev/libs/zglfw/build.zig");
const zgpu = @import("external/zig-gamedev/libs/zgpu/build.zig");
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

    const zgpu_options = zgpu.BuildOptionsStep.init(b, .{
        .uniforms_buffer_size = 64 * 1024 * 1024,
        // .dawn_skip_validation = true,
    });
    const zgpu_pkg = zgpu.getPkg(&.{ zgpu_options.getPkg(), zpool.pkg, zglfw.pkg });

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
    });
    const zd3d12_pkg = zd3d12.getPkg(&.{ zwin32.pkg, zd3d12_options.getPkg() });

    exe.addPackage(zaudio.pkg);
    exe.addPackage(zbullet.pkg);
    exe.addPackage(zgpu_pkg);
    exe.addPackage(zglfw.pkg);
    exe.addPackage(zmesh_pkg);
    exe.addPackage(zmath.pkg);
    exe.addPackage(znoise.pkg);
    exe.addPackage(zpool.pkg);
    exe.addPackage(ztracy_pkg);
    exe.addPackage(zd3d12_pkg);
    exe.addPackage(zwin32.pkg);

    zaudio.link(exe);
    zbullet.link(exe);
    zglfw.link(exe);
    zgpu.link(exe, zgpu_options);
    zmesh.link(exe, zmesh_options);
    znoise.link(exe);
    ztracy.link(exe, ztracy_options);
    zd3d12.link(exe, zd3d12_options);

    exe.install();
    flecs.linkArtifact(b, exe, exe.target, if (exe.target.isWindows()) .static else .exe_compiled, "external/zig-flecs/");

    const run_cmd = exe.run();
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
