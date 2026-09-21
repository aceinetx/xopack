const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const stb = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .link_libc = true,
        .root_source_file = b.path("src/stb.h"),
    });
    stb.addIncludePath(b.path("vendor/stb"));

    const stb_mod = stb.createModule();

    const exe = b.addExecutable(.{
        .name = "xopack",
        .root_module = b.createModule(.{
            .link_libc = true,
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "stb", .module = stb_mod },
            },
        }),
    });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/stb.c") });
    exe.root_module.addIncludePath(b.path("vendor/stb"));

    b.installArtifact(exe);

    const run_step = b.step("run", "Run");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
