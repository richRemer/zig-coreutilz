const std = @import("std");
const QuickBuild = @import("qb.zig").QuickBuild;

pub fn build(b: *std.Build) !void {
    try QuickBuild(.{
        .src_path = "src",
        .deps = .{ .iteropt, .nss },
        .outs = .{
            // programs
            .false = .{ .gen = .{.exe} },
            .seq = .{ .gen = .{.exe}, .zig = .{.iteropt} },
            .sleep = .{ .gen = .{.exe}, .zig = .{.iteropt} },
            .true = .{ .gen = .{.exe} },
            .uname = .{ .gen = .{.exe}, .zig = .{.iteropt} },

            // tests
            .@"test-suite" = .{ .gen = .{.unit}, .zig = .{.nss} },
        },
    }).setup(b);
}
