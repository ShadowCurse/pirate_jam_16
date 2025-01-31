const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const limit_fps: u32 = 240;
    const game_memory_mb: u32 = 128;
    const frame_memory_mb: u32 = 0;
    const scratch_memory_pages: u32 = 4096;
    const max_textures: u32 = 40;
    const max_audio_tracks: u32 = 64;
    const unibuild: bool = target.result.os.tag == .emscripten;
    const stygian = b.dependency("stygian", .{
        .target = target,
        .optimize = optimize,
        .limit_fps = limit_fps,
        .game_memory_mb = game_memory_mb,
        .frame_memory_mb = frame_memory_mb,
        .scratch_memory_pages = scratch_memory_pages,
        .max_textures = max_textures,
        .max_audio_tracks = max_audio_tracks,
        .unibuild = unibuild,
        .software_render = true,
    });
    const s_platform = stygian.module("stygian_platform");
    const s_runtime = stygian.module("stygian_runtime");

    const exe = if (unibuild) blk: {
        const runtime = b.addStaticLibrary(.{
            .name = "unibuild_runtime",
            .root_source_file = b.path("src/runtime.zig"),
            .target = target,
            .optimize = optimize,
        });
        runtime.root_module.addImport("stygian_runtime", s_runtime);

        const platform = if (target.result.os.tag == .emscripten)
            b.addStaticLibrary(.{
                .name = "unibuild_emscripten",
                .root_source_file = b.path("src/platform.zig"),
                .target = target,
                .optimize = optimize,
            })
        else
            b.addExecutable(.{
                .name = "uibuild_platform",
                .root_source_file = b.path("src/platform.zig"),
                .target = target,
                .optimize = optimize,
            });
        platform.root_module.addImport("stygian_platform", s_platform);

        if (target.result.os.tag != .emscripten) {
            platform.linkLibrary(runtime);
            b.installArtifact(platform);
        } else {
            b.installArtifact(platform);
            b.installArtifact(runtime);
        }

        break :blk platform;
    } else blk: {
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

        break :blk platform;
    };

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setEnvironmentVariable("SDL_VIDEODRIVER", "wayland");
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
