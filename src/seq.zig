const std = @import("std");
const iteropt = @import("iteropt");
const coreutilz = @import("lib/coreutilz.zig");
const strings = coreutilz.strings;
const FloatParser = coreutilz.cli.FloatParser;

// TODO: implement format option

var program: coreutilz.Program = undefined;

pub const version =
    \\seq (coreutilz) 0.1
    \\Copyright © 2024, Richard Remer
    \\License MIT: OSI approved license <https://opensource.org/license/mit>
    \\Original seq (GNU coreutils) written by Ulrich Drepper
    \\
;

pub const help =
    \\Usage: {cmd} [OPTION]... LAST
    \\  or:  {cmd} [OPTION]... FIRST LAST
    \\  or:  {cmd} [OPTION]... FIRST INCREMENT LAST
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
    \\
;

const OptionIterator = iteropt.OptIterator("f:s:w", &.{
    "equal-width",
    "format:",
    "separator:",
    "help",
    "version",
});

const seq_strings = struct {
    inv_num: []const u8 = "{s}: invalid floating point argument: '{s}'\n",
    inv_0: []const u8 = "{s}: invalid Zero increment value: '0'\n",
}{};

const SeqOptions = struct {
    equal_width: bool = false,
    format: ?[]const u8 = null,
    separator: []const u8 = "\n",
    first: f64 = 1.0,
    step: f64 = 1.0,
    last: f64 = std.math.nan(f64),

    pub fn init(args: *std.process.ArgIterator) SeqOptions {
        var options = SeqOptions{};
        var it = OptionIterator.init(args);

        while (it.next()) |opt_arg| switch (opt_arg) {
            .terminator => {},
            .option => |opt| switch (opt) {
                .w, .@"equal-width" => options.equal_width = true,
                .f, .format => |arg| options.format = arg,
                .s, .separator => |arg| options.separator = arg,
                .help => program.help(),
                .version => program.version(),
            },
            .argument => |arg1| {
                // simulate GNU getop '+' prefix to short option string
                it.terminated = true;

                if (it.next()) |arg2_opt| {
                    const arg2 = arg2_opt.argument;

                    if (it.next()) |arg3_opt| {
                        const arg3 = arg3_opt.argument;

                        options.first = parse(arg1);
                        options.step = parse(arg2);
                        options.last = parse(arg3);
                    } else {
                        options.first = parse(arg1);
                        options.last = parse(arg2);
                    }
                } else {
                    options.last = parse(arg1);
                }

                if (it.next()) |arg_extra| {
                    program.erruse(strings.op_extra, .{arg_extra.argument});
                }
            },
            .usage => |use| blk: {
                const opt = use.option;

                switch (use.@"error") {
                    .missing_argument => program.erruse(strings.arg_missing, .{opt}),
                    .unexpected_argument => program.erruse(strings.arg_extra, .{opt}),
                    .unknown_option => {
                        // negative numbers look like invalid options
                        if (looks_neg(use.argument)) {
                            // rollback iterator
                            it.terminated = true;
                            it.arg = use.argument;

                            break :blk;
                        } else {
                            program.erruse(strings.inv_opt, .{opt});
                        }
                    },
                }
            },
        };

        if (std.math.isNan(options.last)) {
            program.erruse(strings.op_missing, .{});
        }

        if (options.step == 0.0) {
            // TODO: use actual argument when printing error
            program.erruse(seq_strings.inv_0, .{});
        }

        return options;
    }
};

pub fn main() void {
    var args = std.process.ArgIterator.init();

    program = coreutilz.Program.init(&args);

    const options = SeqOptions.init(&args);
    const desc = options.step < 0;
    const end = options.last;
    var val = options.first;

    if ((desc and val >= end) or (!desc and val <= end)) {
        program.out("{d}", .{val});
        val += options.step;

        while ((desc and val >= end) or (!desc and val <= end)) {
            program.out("{s}{d}", .{ options.separator, val });
            val += options.step;
        }

        program.out("\n", .{});
    }
}

/// Return true if the argument looks like it's a negative number.
fn looks_neg(argument: []const u8) bool {
    if (argument.len < 2) return false;
    if (argument[0] != '-') return false;
    if (argument[1] == '.') return true;
    return argument[1] >= '0' and argument[1] <= '9';
}

/// Parse float arguments.
fn parse(arg: []const u8) f64 {
    return FloatParser(f64, .{ .inf = true }).parse(arg) catch {
        program.erruse(seq_strings.inv_num, .{arg});
    };
}
