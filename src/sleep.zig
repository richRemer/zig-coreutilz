const std = @import("std");
const iteropt = @import("iteropt");
const coreutilz = @import("lib/coreutilz.zig");
const FloatParser = coreutilz.cli.FloatParser;
const strings = coreutilz.strings;

var program: coreutilz.Program = undefined;

pub const version =
    \\sleep (coreutilz) 0.1
    \\Copyright © 2024, Richard Remer
    \\License MIT: OSI approved license <https://opensource.org/license/mit>
    \\Original sleep (GNU coreutils) written by Jim Meyering and Paul Eggert
    \\
;

pub const help =
    \\Usage: {cmd} NUMBER[SUFFIX]...
    \\  or:  {cmd} OPTION
    \\Pause for NUMBER seconds.  SUFFIX may be 's' for seconds (the default),
    \\'m' for minutes, 'h' for hours or 'd' for days.  NUMBER need not be an
    \\integer.  Given two or more arguments, pause for the amount of time
    \\specified by the sum of their values.
    \\
    \\      --help        display this help and exit
    \\      --version     output version information and exit
    \\
;

const OptionIterator = iteropt.OptIterator("", &.{
    "help",
    "version",
});

const sleep_strings = struct {
    inv_interval: []const u8 = "{s}: invalid time interval '{s}'\n",
}{};

/// Supported user provided units.  Enum values are in nanoseconds.
const SleepUnit = enum(u64) {
    s = 1 * 1_000_000_000,
    m = 60 * 1_000_000_000,
    h = 60 * 60 * 1_000_000_000,
    d = 60 * 60 * 24 * 1_000_000_000,
};

const SleepOptions = struct {
    nanoseconds: u64,

    pub fn init(args: *std.process.ArgIterator) SleepOptions {
        const Float = FloatParser(f64, .{ .inf = true });

        var op_missing = true;
        var options = SleepOptions{ .nanoseconds = 0 };
        var it = OptionIterator.init(args);

        while (it.next()) |opt_arg| switch (opt_arg) {
            .terminator => {},
            .option => |opt| switch (opt) {
                .help => program.help(),
                .version => program.version(),
            },
            .argument => |arg| {
                var num = arg;
                const unit_ch: u8 = if (arg.len > 1) arg[arg.len - 1] else ' ';
                const maybe_unit = switch (unit_ch) {
                    's' => SleepUnit.s,
                    'm' => SleepUnit.m,
                    'h' => SleepUnit.h,
                    'd' => SleepUnit.d,
                    else => null,
                };

                if (maybe_unit) |_| {
                    num = arg[0 .. arg.len - 1];
                }

                const unit = @intFromEnum(maybe_unit orelse SleepUnit.s);
                const factor: f64 = @floatFromInt(unit);
                const val = Float.parse(num) catch {
                    program.erruse(sleep_strings.inv_interval, .{arg});
                };

                op_missing = false;
                options.nanoseconds += @intFromFloat(val * factor);
            },
            .usage => |use| {
                const opt = use.option;

                switch (use.@"error") {
                    .missing_argument => unreachable,
                    .unexpected_argument => unreachable,
                    .unknown_option => program.erruse(strings.inv_opt, .{opt}),
                }
            },
        };

        if (op_missing) {
            program.erruse(strings.op_missing, .{});
        }

        return options;
    }
};

pub fn main() void {
    var args = std.process.ArgIterator.init();

    program = coreutilz.Program.init(&args);

    const options = SleepOptions.init(&args);

    std.time.sleep(options.nanoseconds);
}
