//! Module for working with command command-line arguments.

const std = @import("std");
const NSS = @import("nss").NSS;
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const mockFile = @import("nss").testing.mockFile;

/// Error set resulting from parsing a floating point argument and getting an
/// invalid result.
const InvalidFloatError = error{
    InvalidCharacter,
    InvalidNanValue,
    InvalidInfValue,
};

/// Options to control parsing floating point argument.
pub const FloatOptions = struct {
    /// Return NaN for invalid value instead of error.
    nan: bool = false,
    /// Accept infinite values.
    inf: bool = false,
};

/// Parse floating point argument.
pub fn FloatParser(comptime T: type, comptime options: FloatOptions) type {
    const Result = if (options.nan) T else InvalidFloatError!T;

    return struct {
        pub fn parse(arg: []const u8) Result {
            if (fmt.parseFloat(T, arg)) |float| {
                if (math.isInf(float)) {
                    if (options.inf) return float;
                    if (options.nan) return math.nan(T);
                    return InvalidFloatError.InvalidInfValue;
                } else if (math.isNan(float)) {
                    if (options.nan) return float;
                    return InvalidFloatError.InvalidNanValue;
                } else {
                    return float;
                }
            } else |err| {
                return if (options.nan) math.nan(T) else err;
            }
        }
    };
}

/// Parsed file owner.
pub const OwnerArgument = struct {
    /// Original argument before parsing.
    arg: []const u8,
    /// Resulting UID of parsed value after lookup in NSS passwd database.
    uid: ?u32,
    /// Resulting GID of parsed value after lookup in NSS group database.
    gid: ?u32,
};

/// Parse file owner argument in the form [USER[:[GROUP]]].
pub const OwnerParser = struct {
    nss: *NSS,

    pub fn init(nss: *NSS) OwnerParser {
        return .{ .nss = nss };
    }

    /// Parse argument and return structure describing parsed result.
    pub fn parse(this: OwnerParser, arg: []const u8) !OwnerArgument {
        return readOwner(this.nss, arg);
    }
};

/// Read owner argument, looking up parsed user and group in the NSS database
/// to provide UID and GID results.
fn readOwner(nss: *NSS, arg: []const u8) !OwnerArgument {
    var uid: ?u32 = null;
    var gid: ?u32 = null;
    var has_dot: bool = false;
    var delim: ?usize = null;

    if (mem.indexOfScalar(u8, arg, ':')) |colon| {
        delim = colon;
    } else if (mem.indexOfScalar(u8, arg, '.')) |dot| {
        has_dot = true;
        delim = dot;
    }

    if (has_dot) {
        if (lookupOwner(nss, arg, "", false, &uid, &gid)) {
            return .{ .arg = arg, .uid = uid, .gid = gid };
        } else |err| {
            // ignore; will try again using dot delimiter
            err catch {};
        }
    }

    const user = if (delim) |pos| arg[0..pos] else arg;
    const group = if (delim) |pos| arg[pos + 1 ..] else "";

    try lookupOwner(nss, user, group, delim != null, &uid, &gid);
    return .{ .arg = arg, .uid = uid, .gid = gid };
}

/// Lookup user and group in NSS database and set uid_out and gid_out to the
/// UID and GID specified in user and group.  The results match those described
/// by `info coreutils 'chown invocation'`; values may be null if user or group
/// are empty.
fn lookupOwner(
    nss: *NSS,
    user: []const u8,
    group: []const u8,
    has_delim: bool,
    uid_out: *?u32,
    gid_out: *?u32,
) !void {
    var uid: ?u32 = null;
    var gid: ?u32 = null;

    const use_login_group = group.len == 0 and has_delim;

    if (user.len > 0) {
        if (nss.getpwnam(user)) |entry| {
            uid = entry.uid;

            if (use_login_group) {
                gid = entry.gid;
            }
        } else if (use_login_group) {
            return error.InvalidSpec;
        } else if (fmt.parseInt(u32, user, 10)) |id| {
            uid = id;
        } else |err| {
            err catch return error.InvalidUser;
        }
    }

    if (group.len > 0) {
        if (nss.getgrnam(group)) |entry| {
            gid = entry.gid;
        } else if (fmt.parseInt(u32, group, 10)) |id| {
            gid = id;
        } else |err| {
            err catch return error.InvalidGroup;
        }
    }

    uid_out.* = uid;
    gid_out.* = gid;
}

test "parse well-formed float" {
    const Float = FloatParser(f64, .{});

    try std.testing.expectEqual(1.0, Float.parse("1"));
    try std.testing.expectEqual(3.14159, Float.parse("3.14159"));
    try std.testing.expectEqual(6.022e23, Float.parse("6.022E23"));
    try std.testing.expectEqual(6.62607015e-34, Float.parse("6.62607015e-34"));
}

test "parse malformed float" {
    const FloatErr = FloatParser(f64, .{});
    const FloatNaN = FloatParser(f64, .{ .nan = true });

    try std.testing.expectError(InvalidFloatError.InvalidCharacter, FloatErr.parse("foo"));
    try std.testing.expect(math.isNan(FloatNaN.parse("foo")));
}

test "parse explicit NaN" {
    const FloatErr = FloatParser(f64, .{});
    const FloatNaN = FloatParser(f64, .{ .nan = true });

    try std.testing.expectError(InvalidFloatError.InvalidNanValue, FloatErr.parse("nan"));
    try std.testing.expect(math.isNan(FloatNaN.parse("nan")));
}

test "parse infinity" {
    const FloatErr = FloatParser(f64, .{});
    const FloatNaN = FloatParser(f64, .{ .nan = true });
    const FloatInf = FloatParser(f64, .{ .nan = true, .inf = true });

    try std.testing.expectError(InvalidFloatError.InvalidInfValue, FloatErr.parse("inf"));
    try std.testing.expect(math.isNan(FloatNaN.parse("inf")));
    try std.testing.expect(math.isInf(FloatInf.parse("inf")));
}

test "parse 'user:group' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse("foo:adm");

    try std.testing.expectEqualStrings("foo:adm", owner.arg);
    try std.testing.expectEqual(1000, owner.uid);
    try std.testing.expectEqual(100, owner.gid);
}

test "parse 'user:' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse("foo:");

    try std.testing.expectEqualStrings("foo:", owner.arg);
    try std.testing.expectEqual(1000, owner.uid);
    try std.testing.expectEqual(1000, owner.gid);
}

test "parse 'user' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse("foo");

    try std.testing.expectEqualStrings("foo", owner.arg);
    try std.testing.expectEqual(1000, owner.uid);
    try std.testing.expectEqual(null, owner.gid);
}

test "parse ':group' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse(":foo");

    try std.testing.expectEqualStrings(":foo", owner.arg);
    try std.testing.expectEqual(null, owner.uid);
    try std.testing.expectEqual(1000, owner.gid);
}

test "parse 'UID:GID' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse("1001:1002");

    try std.testing.expectEqualStrings("1001:1002", owner.arg);
    try std.testing.expectEqual(1001, owner.uid);
    try std.testing.expectEqual(1002, owner.gid);
}

test "parse 'UID:' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    try std.testing.expectError(error.InvalidSpec, parser.parse("1001:"));
}

test "parse 'UID' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse("1001");

    try std.testing.expectEqualStrings("1001", owner.arg);
    try std.testing.expectEqual(1001, owner.uid);
    try std.testing.expectEqual(null, owner.gid);
}

test "parse ':GID' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse(":1002");

    try std.testing.expectEqualStrings(":1002", owner.arg);
    try std.testing.expectEqual(null, owner.uid);
    try std.testing.expectEqual(1002, owner.gid);
}

test "parse unknown 'user:group' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    try std.testing.expectError(error.InvalidUser, parser.parse("bar:baz"));
}

test "parse unknown 'user' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    try std.testing.expectError(error.InvalidUser, parser.parse("bar"));
}

test "parse unknown ':group' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    try std.testing.expectError(error.InvalidGroup, parser.parse(":bar"));
}

test "parse ':' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse(":");

    try std.testing.expectEqualStrings(":", owner.arg);
    try std.testing.expectEqual(null, owner.uid);
    try std.testing.expectEqual(null, owner.gid);
}

test "parse '' owner" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const parser = OwnerParser.init(&nss);
    const owner = try parser.parse("");

    try std.testing.expectEqualStrings("", owner.arg);
    try std.testing.expectEqual(null, owner.uid);
    try std.testing.expectEqual(null, owner.gid);
}

fn nssMock(nss: *NSS) !void {
    const passwd = "passwd: files\n";
    const group = "group: files\n";
    const root_user = "root:x:0:0:root:/root:/bin/bash\n";
    const foo_user = "foo:x:1000:1000:Foo User:/home/foo:/bin/bash\n";
    const root_group = "root:x:0:\n";
    const adm_group = "adm:x:100:foo\n";
    const foo_group = "foo:x:1000:\n";
    const users = root_user ++ foo_user;
    const groups = root_group ++ adm_group ++ foo_group;

    try mockFile(nss, "/etc/nsswitch.conf", passwd ++ group);
    try mockFile(nss, "/etc/passwd", users);
    try mockFile(nss, "/etc/group", groups);
}
