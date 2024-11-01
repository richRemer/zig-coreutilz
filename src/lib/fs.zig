const std = @import("std");
const fs = std.fs;
const posix = std.posix;

/// Error set resulting from error statting a file path.
pub const PStatError = fs.File.OpenError || posix.FStatError;

/// Return information about a filesystem path.
pub fn pstat(path: []const u8) PStatError!std.posix.Stat {
    const file = try fs.cwd().openFile(path, .{});
    defer file.close();

    return try posix.fstat(file.handle);
}
