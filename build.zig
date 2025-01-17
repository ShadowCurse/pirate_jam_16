const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const unibuild: bool = false;
    const stygian = b.dependency("stygian", .{
        .target = target,
        .optimize = optimize,
        .unibuild = unibuild,
        .software_render = true,
    });
    const s_platform = stygian.module("stygian_platform");
    const s_runtime = stygian.module("stygian_runtime");

    const runtime = b.addSharedLibrary(.{
        .name = "runtime",
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime.root_module.addImport("stygian_runtime", s_runtime);
    b.installArtifact(runtime);

    const platform = b.addExecutable(.{
        .name = "platform",
        .root_source_file = b.path("src/platform.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform.root_module.addImport("stygian_platform", s_platform);
    b.installArtifact(platform);

    if (unibuild)
        platform.linkLibrary(runtime);

    const run_cmd = b.addRunArtifact(platform);
    run_cmd.setEnvironmentVariable("SDL_VIDEODRIVER", "wayland");
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
