const std = @import("std");
const Builder = std.build.Builder;

const flecs = @import("external/zig-flecs/build.zig");
// const glfw = @import("external/zig-gamedev/libs/mach-glfw/build.zig");
const zbullet = @import("external/zig-gamedev/libs/zbullet/build.zig");
const zgpu = @import("external/zig-gamedev/libs/zgpu/build.zig");
const zmath = @import("external/zig-gamedev/libs/zmath/build.zig");
const zmesh = @import("external/zig-gamedev/libs/zmesh/build.zig");
const znoise = @import("external/zig-gamedev/libs/znoise/build.zig");
const zpool = @import("external/zig-gamedev/libs/zpool/build.zig");

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("ElvengroinLegacy", "src/main.zig");

    exe.setTarget(b.standardTargetOptions(.{}));
    exe.setBuildMode(b.standardReleaseOptions());

    exe.addPackagePath("zigimg", "external/zigimg/zigimg.zig");
    // exe.addPackagePath("qoi", "external/zig-qoi/src/qoi.zig");
    exe.addPackagePath("args", "external/zig-args/args.zig");

    const zgpu_options = zgpu.BuildOptionsStep.init(b, .{ .dawn = .{ .from_source = false } });
    const zgpu_pkg = zgpu.getPkg(&.{ zgpu_options.getPkg(), zpool.pkg });
    // const zgpu_options = zgpu.BuildOptionsStep.init(b, .{ .dawn = .{ .from_source = false } });
    // const zgpu_pkg = zgpu.getPkg(&.{ zgpu_options.getPkg(), glfw.pkg });

    const zmesh_options = zmesh.BuildOptionsStep.init(b, .{});
    const zmesh_pkg = zmesh.getPkg(&.{zmesh_options.getPkg()});

    // exe.addPackage(glfw.pkg);
    exe.addPackage(zbullet.pkg);
    exe.addPackage(zgpu_pkg);
    exe.addPackage(zmesh_pkg);
    exe.addPackage(zmath.pkg);
    exe.addPackage(znoise.pkg);
    exe.addPackage(zpool.pkg);

    zbullet.link(exe);
    zgpu.link(exe, zgpu_options);
    zmesh.link(exe, zmesh_options);
    znoise.link(exe);

    exe.install();
    flecs.linkArtifact(b, exe, exe.target, if (exe.target.isWindows()) .static else .exe_compiled, "external/zig-flecs/");

    // const compile_step = b.step("compile", "Compiles src/main.zig");
    // compile_step.dependOn(&exe.step);

    // const install_exe = b.addInstallArtifact(exe);
    // b.getInstallStep().dependOn(&install_exe.step);

    // const run_step = std.build.RunStep.create(exe.builder, "run egl");
    const run_cmd = exe.run();
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    // run_step.addArtifactArg(exe);
    // run_step.step.dependOn(b.getInstallStep());

    // const step = b.step("run", "Runs the executable");
    // step.dependOn(&run_step.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
