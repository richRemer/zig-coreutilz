test {
    const std = @import("std");
    const testing = std.testing;
    const owner = @import("lib/cli.zig");

    testing.refAllDecls(@This());
    _ = owner;
}
