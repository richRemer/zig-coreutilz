//! Module for working with POSIX-style file ownership, providing parsing for
//! command-line options programs expect when specifying file ownership.

const std = @import("std");
const NSS = @import("nss").NSS;
const mockFile = @import("nss").testing.mockFile;
const fmt = std.fmt;
const mem = std.mem;

pub const Spec = struct {
    source: []const u8,
    uid: ?u32,
    gid: ?u32,

    pub const Ids = struct {
        uid: ?u32,
        gid: ?u32,
    };

    pub fn init(nss: *NSS, source: []const u8) !Spec {
        var has_dot: bool = false;
        var delim: ?usize = null;

        if (mem.indexOfScalar(u8, source, ':')) |colon| {
            delim = colon;
        } else if (mem.indexOfScalar(u8, source, '.')) |dot| {
            has_dot = true;
            delim = dot;
        }

        if (has_dot) {
            if (Spec.lookup(nss, source, "", false)) |ids| {
                return .{ .source = source, .uid = ids.uid, .gid = ids.gid };
            } else |err| {
                // ignore; will try again using dot delimiter
                err catch {};
            }
        }

        const user = if (delim) |pos| source[0..pos] else source;
        const group = if (delim) |pos| source[pos + 1 ..] else "";
        const ids = try Spec.lookup(nss, user, group, delim != null);

        return .{ .source = source, .uid = ids.uid, .gid = ids.gid };
    }

    fn lookup(
        nss: *NSS,
        user: []const u8,
        group: []const u8,
        has_delim: bool,
    ) !Ids {
        var ids: Ids = .{ .uid = null, .gid = null };

        const use_login_group = group.len == 0 and has_delim;

        if (user.len > 0) {
            if (nss.getpwnam(user)) |entry| {
                ids.uid = entry.uid;

                if (use_login_group) {
                    ids.gid = entry.gid;
                }
            } else if (use_login_group) {
                return error.InvalidSpec;
            } else if (fmt.parseInt(u32, user, 10)) |id| {
                ids.uid = id;
            } else |err| {
                err catch return error.InvalidUser;
            }
        }

        if (group.len > 0) {
            if (nss.getgrnam(group)) |entry| {
                ids.gid = entry.gid;
            } else if (fmt.parseInt(u32, group, 10)) |id| {
                ids.gid = id;
            } else |err| {
                err catch return error.InvalidGroup;
            }
        }

        return ids;
    }
};

test "handle 'user:group' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, "foo:adm");

    try std.testing.expectEqualStrings("foo:adm", spec.source);
    try std.testing.expectEqual(1000, spec.uid);
    try std.testing.expectEqual(100, spec.gid);
}

test "handle 'user:' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, "foo:");

    try std.testing.expectEqualStrings("foo:", spec.source);
    try std.testing.expectEqual(1000, spec.uid);
    try std.testing.expectEqual(1000, spec.gid);
}

test "handle 'user' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, "foo");

    try std.testing.expectEqualStrings("foo", spec.source);
    try std.testing.expectEqual(1000, spec.uid);
    try std.testing.expectEqual(null, spec.gid);
}

test "handle ':group' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, ":foo");

    try std.testing.expectEqualStrings(":foo", spec.source);
    try std.testing.expectEqual(null, spec.uid);
    try std.testing.expectEqual(1000, spec.gid);
}

test "handle 'UID:GID' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, "1001:1002");

    try std.testing.expectEqualStrings("1001:1002", spec.source);
    try std.testing.expectEqual(1001, spec.uid);
    try std.testing.expectEqual(1002, spec.gid);
}

test "handle 'UID:' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);
    try std.testing.expectError(error.InvalidSpec, Spec.init(&nss, "1001:"));
}

test "handle 'UID' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, "1001");

    try std.testing.expectEqualStrings("1001", spec.source);
    try std.testing.expectEqual(1001, spec.uid);
    try std.testing.expectEqual(null, spec.gid);
}

test "handle ':GID' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, ":1002");

    try std.testing.expectEqualStrings(":1002", spec.source);
    try std.testing.expectEqual(null, spec.uid);
    try std.testing.expectEqual(1002, spec.gid);
}

test "handle unknown 'user:group' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);
    try std.testing.expectError(error.InvalidUser, Spec.init(&nss, "bar:baz"));
}

test "handle unknown 'user' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);
    try std.testing.expectError(error.InvalidUser, Spec.init(&nss, "bar"));
}

test "handle unknown ':group' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);
    try std.testing.expectError(error.InvalidGroup, Spec.init(&nss, ":bar"));
}

test "handle ':' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, ":");

    try std.testing.expectEqualStrings(":", spec.source);
    try std.testing.expectEqual(null, spec.uid);
    try std.testing.expectEqual(null, spec.gid);
}

test "handle '' spec" {
    var nss = NSS.open(std.testing.allocator);
    defer nss.close();

    try nssMock(&nss);

    const spec = try Spec.init(&nss, "");

    try std.testing.expectEqualStrings("", spec.source);
    try std.testing.expectEqual(null, spec.uid);
    try std.testing.expectEqual(null, spec.gid);
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
