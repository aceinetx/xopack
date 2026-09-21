const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --------------------------------------------------------------

    const stb = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .link_libc = true,
        .root_source_file = b.path("xopack/stb.h"),
    });
    stb.addIncludePath(b.path("vendor/stb"));

    const stb_mod = stb.createModule();
    stb_mod.addCSourceFile(.{ .file = b.path("xopack/stb.c") });
    stb_mod.addIncludePath(b.path("vendor/stb"));

    const xopack = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .root_source_file = b.path("xopack/root.zig"),
        .imports = &.{
            .{ .name = "stb", .module = stb_mod },
        },
    });

    // --------------------------------------------------------------

    const exe = b.addExecutable(.{
        .name = "xopack",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/root.zig"),
            .imports = &.{
                .{ .name = "xopack", .module = xopack },
            },
        }),
    });

    b.installArtifact(exe);

    // --------------------------------------------------------------

    const run_step = b.step("run", "Run");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
