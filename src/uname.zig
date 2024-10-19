const std = @import("std");
const builtin = @import("builtin");
const iteropt = @import("iteropt");
const coreutilz = @import("lib/coreutilz.zig");
const strings = coreutilz.strings;

var program: coreutilz.Program = undefined;

pub const version =
    \\uname (coreutilz) 0.1
    \\Copyright © 2024, Richard Remer
    \\License MIT: OSI approved license <https://opensource.org/license/mit>
    \\Original uname (GNU coreutils) written by David MacKenzie
    \\
;

pub const help =
    \\Usage: {cmd} [OPTION]...
    \\Print certain system information.  With no OPTION, same as -s.
    \\
    \\  -a, --all                print all information, in the following order,
    \\                             except omit -p and -i if unknown:
    \\  -s, --kernel-name        print the kernel name
    \\  -n, --nodename           print the network node hostname
    \\  -r, --kernel-release     print the kernel release
    \\  -v, --kernel-version     print the kernel version
    \\  -m, --machine            print the machine hardware name
    \\  -p, --processor          print the processor type (non-portable)
    \\  -i, --hardware-platform  print the hardware platform (non-portable)
    \\  -o, --operating-system   print the operating system
    \\      --help               display this help and exit
    \\      --version            output version information and exit
    \\
;

const OptionIterator = iteropt.OptIterator("aimnoprsv", &.{
    "all",
    "hardware-platform",
    "kernel-name",
    "kernel-release",
    "kernel-version",
    "machine",
    "nodename",
    "operating-system",
    "processor",
    "release", // deprecated
    "sysname", // deprecated
    "help",
    "version",
});

const UnameOptions = packed struct(u8) {
    hardware_platform: bool = false,
    kernel_name: bool = false,
    kernel_release: bool = false,
    kernel_version: bool = false,
    machine: bool = false,
    nodename: bool = false,
    operating_system: bool = false,
    processor: bool = false,

    pub fn init(args: *std.process.ArgIterator) UnameOptions {
        var options = UnameOptions{};
        var it = OptionIterator.init(args);

        while (it.next()) |opt_arg| switch (opt_arg) {
            .terminator => {},
            .option => |opt| switch (opt) {
                .a, .all => options.enableAll(),
                .i, .@"hardware-platform" => options.hardware_platform = true,
                .m, .machine => options.machine = true,
                .n, .nodename => options.nodename = true,
                .o, .@"operating-system" => options.operating_system = true,
                .p, .processor => options.processor = true,
                .r, .@"kernel-release", .release => options.kernel_release = true,
                .s, .@"kernel-name", .sysname => options.kernel_name = true,
                .v, .@"kernel-version" => options.kernel_version = true,
                .help => program.help(),
                .version => program.version(),
            },
            .argument => |arg| program.erruse(strings.op_extra, .{arg}),
            .usage => |use| {
                const opt = use.option;

                switch (use.@"error") {
                    .missing_argument => program.erruse(strings.arg_missing, .{opt}),
                    .unexpected_argument => program.erruse(strings.arg_extra, .{opt}),
                    .unknown_option => program.erruse(strings.op_missing, .{}),
                }
            },
        };

        if (0 == @as(u8, @bitCast(options))) {
            options.operating_system = true;
        }

        return options;
    }

    pub fn enableAll(this: *UnameOptions) void {
        this.hardware_platform = true;
        this.kernel_name = true;
        this.kernel_release = true;
        this.kernel_version = true;
        this.machine = true;
        this.nodename = true;
        this.operating_system = true;
        this.processor = true;
    }
};

pub fn main() void {
    var args = std.process.ArgIterator.init();
    var utsname: std.os.linux.utsname = undefined;

    program = coreutilz.Program.init(&args);

    const linux = std.os.linux;
    const options = UnameOptions.init(&args);
    const uname_err = linux.E.init(linux.uname(&utsname));

    if (uname_err != .SUCCESS) {
        program.err("{s}: cannot get system name: {s}\n", .{
            program.cmd,
            @tagName(uname_err),
        });
        std.process.exit(1);
    }

    var printer = TokenPrinter{};

    if (options.kernel_name) printer.print(&utsname.sysname);
    if (options.nodename) printer.print(&utsname.nodename);
    if (options.kernel_release) printer.print(&utsname.release);
    if (options.kernel_version) printer.print(&utsname.version);
    if (options.machine) printer.print(&utsname.machine);

    // if -a option used, skip processor and hardware_platform
    if (0xff != @as(u8, @bitCast(options))) {
        if (options.processor) printer.print(@tagName(builtin.cpu.arch));
        if (options.hardware_platform) printer.print("unknown");
    }

    // TODO: ensure case matches
    if (options.operating_system) printer.print(@tagName(builtin.os.tag));

    program.out("\n", .{});
}

const TokenPrinter = struct {
    printed: bool = false,

    pub fn print(this: *TokenPrinter, value: []const u8) void {
        if (!this.printed) {
            program.out("{s}", .{value});
            this.printed = true;
        } else {
            program.out(" {s}", .{value});
        }
    }
};
