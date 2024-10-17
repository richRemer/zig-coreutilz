const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const iteropt = b.dependency("iteropt", .{
        .target = target,
        .optimize = optimize,
    });

    const seq = b.addExecutable(.{
        .name = "seq",
        .root_source_file = b.path("src/seq.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_seq = b.addRunArtifact(seq);

    seq.root_module.addImport("iteropt", iteropt.module("iteropt"));
    b.installArtifact(seq);
    b.step("seq", "run 'seq' command").dependOn(&run_seq.step);

    if (b.args) |args| {
        run_seq.addArgs(args);
    }
}
