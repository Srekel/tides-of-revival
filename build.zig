const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const exe = b.addExecutable("ElvengroinLegacy", "src/main.zig");

    exe.setTarget(b.standardTargetOptions(.{}));
    exe.setBuildMode(b.standardReleaseOptions());

    // exe.addPackagePath("zmath", "external/zig-gamedev/libs/zmath/zmath.zig");
    exe.install();

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
