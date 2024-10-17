const std = @import("std");
const iteropt = @import("iteropt");

// TODO: implement format option

const OptionIterator = iteropt.OptIterator("f:s:w", &.{
    "equal-width",
    "format:",
    "separator:",
    "help",
    "version",
});

const strings = struct {
    null_argv0: []const u8 = "A NULL argv[0] was passed through an exec system call.\n",
    op_missing: []const u8 = "{s}: missing operand\n",
    op_extra: []const u8 = "{s}: extra operand '{s}'\n",
    arg_missing: []const u8 = "{s}: option requires an argument -- '{s}'\n",
    arg_extra: []const u8 = "{s}: option '--{s}' doesn't allow an argument\n",
    inv_opt: []const u8 = "{s}: invalid option '{s}'\n",
    inv_num: []const u8 = "{s}: invalid floating point argument: '{s}'\n",
    inv_0: []const u8 = "{s}: invalid Zero increment value: '0'\n",
    try_help: []const u8 = "Try '{s} --help' for more information.\n",
}{};

const SeqOptions = struct {
    program_name: []const u8,
    equal_width: bool = false,
    format: ?[]const u8 = null,
    separator: []const u8 = "\n",
    first: f64 = 1.0,
    step: f64 = 1.0,
    last: f64 = std.math.nan(f64),

    pub fn init(args: *std.process.ArgIterator) SeqOptions {
        const arg0 = args.next();

        if (arg0 == null) {
            err(strings.null_argv0, .{});
            std.process.exit(134); // SIGABRT
        }

        const float = FloatParser(f64).init(arg0.?);
        var options = SeqOptions{ .program_name = arg0.? };
        var it = OptionIterator.init(args);

        while (it.next()) |opt_arg| switch (opt_arg) {
            .terminator => {},
            .option => |opt| switch (opt) {
                .w, .@"equal-width" => options.equal_width = true,
                .f, .format => |arg| options.format = arg,
                .s, .separator => |arg| options.separator = arg,
                .help => help(options.program_name),
                .version => version(),
            },
            .argument => |arg1| {
                // simulate GNU getop '+' prefix to short option string
                it.terminated = true;

                if (it.next()) |arg2_opt| {
                    const arg2 = arg2_opt.argument;

                    if (it.next()) |arg3_opt| {
                        const arg3 = arg3_opt.argument;

                        options.first = float.parse(arg1);
                        options.step = float.parse(arg2);
                        options.last = float.parse(arg3);
                    } else {
                        options.first = float.parse(arg1);
                        options.last = float.parse(arg2);
                    }
                } else {
                    options.last = float.parse(arg1);
                }

                if (it.next()) |arg_extra| {
                    const cmd = options.program_name;
                    const arg = arg_extra.argument;
                    err(strings.op_extra, .{ cmd, arg });
                    std.process.exit(1);
                }
            },
            .usage => |use| blk: {
                const cmd = options.program_name;
                const opt = use.option;

                switch (use.@"error") {
                    .missing_argument => err(strings.arg_missing, .{ cmd, opt }),
                    .unexpected_argument => err(strings.arg_extra, .{ cmd, opt }),
                    .unknown_option => {
                        // negative numbers look like invalid options
                        if (looks_neg(use.argument)) {
                            // rollback iterator
                            it.terminated = true;
                            it.arg = use.argument;

                            break :blk;
                        } else {
                            err(strings.inv_opt, .{ cmd, opt });
                        }
                    },
                }

                err(strings.try_help, .{options.program_name});
                std.process.exit(1);
            },
        };

        if (std.math.isNan(options.last)) {
            err(strings.op_missing, .{options.program_name});
            std.process.exit(1);
        }

        if (options.step == 0.0) {
            // TODO: use actual argument when printing error
            err(strings.inv_0, .{options.program_name});
            std.process.exit(1);
        }

        return options;
    }
};

pub fn main() void {
    var args = std.process.ArgIterator.init();
    const options = SeqOptions.init(&args);
    const desc = options.step < 0;
    const end = options.last;
    var val = options.first;

    if ((desc and val >= end) or (!desc and val <= end)) {
        out("{d}", .{val});
        val += options.step;

        while ((desc and val >= end) or (!desc and val <= end)) {
            out("{s}{d}", .{ options.separator, val });
            val += options.step;
        }

        out("\n", .{});
    }
}

/// Display help and exit.
fn help(cmd: []const u8) void {
    out(
        \\Usage: {s} [OPTION]... LAST
        \\  or:  {s} [OPTION]... FIRST LAST
        \\  or:  {s} [OPTION]... FIRST INCREMENT LAST
        \\Print numbers from FIRST to LAST, in steps of INCREMENT.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -f, --format=FORMAT      use printf style floating-point FORMAT
        \\  -s, --separator=STRING   use STRING to separate numbers (default: \n)
        \\  -w, --equal-width        equalize width by padding with leading zeroes
        \\      --help               display this help and exit
        \\      --version            output version information and exit
        \\
        \\If FIRST or INCREMENT is omitted, it defaults to 1.  That is, an
        \\omitted INCREMENT defaults to 1 even when LAST is smaller than FIRST.
        \\The sequence of numbers ends when the sum of the current number and
        \\INCREMENT would become greater than LAST.
        \\FIRST, INCREMENT, and LAST are interpreted as floating point values.
        \\INCREMENT is usually positive if FIRST is smaller than LAST, and
        \\INCREMENT is usually negative if FIRST is greater than LAST.
        \\INCREMENT must not be 0; none of FIRST, INCREMENT and LAST may be NaN.
        \\FORMAT must be suitable for printing one argument of type 'double';
        \\it defaults to %.PRECf if FIRST, INCREMENT, and LAST are all fixed point
        \\decimal numbers with maximum precision PREC, and to %g otherwise.
    , .{ cmd, cmd, cmd });
    std.process.exit(0);
}

/// Display version and exit.
fn version() void {
    out(
        \\seq (coreutilz) 0.1
        \\Copyright © 2024, Richard Remer
        \\Original seq (GNU coreutils) written by Ulrich Drepper
    , .{});
    std.process.exit(0);
}

/// Non-blocking, safe write to STDERR
fn err(comptime format: []const u8, args: anytype) void {
    const writer = std.io.getStdErr().writer();
    writer.print(format, args) catch {};
}

/// Non-blocking, safe write to STDOUT
fn out(comptime format: []const u8, args: anytype) void {
    const writer = std.io.getStdOut().writer();
    writer.print(format, args) catch {};
}

/// Return true if the argument looks like it's a negative number.
fn looks_neg(argument: []const u8) bool {
    if (argument.len < 2) return false;
    if (argument[0] != '-') return false;
    if (argument[1] == '.') return true;
    return argument[1] >= '0' and argument[1] <= '9';
}

/// Parse float arguments.
fn FloatParser(comptime T: type) type {
    return struct {
        program_name: []const u8,

        pub fn init(program_name: []const u8) @This() {
            return .{ .program_name = program_name };
        }

        /// Parse float or exit with error.
        pub fn parse(this: @This(), arg: []const u8) T {
            if (std.fmt.parseFloat(T, arg)) |float| {
                if (std.math.isNan(float)) {
                    this.exit(arg);
                } else {
                    return float;
                }
            } else |_| {
                this.exit(arg);
            }
        }

        /// Write error and exit.
        fn exit(this: @This(), arg: []const u8) noreturn {
            err(strings.inv_num, .{ this.program_name, arg });
            err(strings.try_help, .{this.program_name});
            std.process.exit(1);
        }
    };
}
