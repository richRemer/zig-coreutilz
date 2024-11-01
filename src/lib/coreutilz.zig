const std = @import("std");
const root = @import("root");

pub const cli = @import("cli.zig");
pub const fs = @import("fs.zig");

/// Common strings used by many tools.
pub const strings = struct {
    arg_missing: []const u8 = "{s}: option requires an argument -- '{s}'\n",
    arg_extra: []const u8 = "{s}: option '--{s}' doesn't allow an argument\n",
    inv_opt: []const u8 = "{s}: invalid option '{s}'\n",
    no_mem: []const u8 = "{s}: memory exhausted\n",
    null_argv0: []const u8 = "A NULL argv[0] was passed through an exec system call.\n",
    op_missing: []const u8 = "{s}: missing operand\n",
    op_extra: []const u8 = "{s}: extra operand '{s}'\n",
    try_help: []const u8 = "Try '{s} --help' for more information.\n",
}{};

pub const Program = struct {
    cmd: []const u8,
    stdout: std.fs.File.Writer,
    stderr: std.fs.File.Writer,

    pub fn init(args: *std.process.ArgIterator) Program {
        const stdout = std.io.getStdOut().writer();
        const stderr = std.io.getStdErr().writer();
        const arg0 = args.next();

        if (arg0 == null) {
            @panic(strings.null_argv0);
        }

        return .{
            .cmd = arg0.?,
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    /// Non-blocking, safe write to STDERR
    pub fn err(
        this: Program,
        comptime format: []const u8,
        args: anytype,
    ) void {
        this.stderr.print(format, args) catch {};
    }

    /// Print error and exit.
    pub fn errexit(
        this: Program,
        status: u8,
        comptime format: []const u8,
        args: anytype,
    ) noreturn {
        this.errprog(format, args);
        std.process.exit(status);
    }

    /// Print error with program name.
    pub fn errprog(
        this: Program,
        comptime format: []const u8,
        args: anytype,
    ) void {
        const program_args = .{this.cmd};
        this.err(format, program_args ++ args);
    }

    /// Print usage error and exit.
    pub fn erruse(
        this: Program,
        comptime format: []const u8,
        args: anytype,
    ) noreturn {
        this.errprog(format, args);
        this.errprog(strings.try_help, .{});
        std.process.exit(1);
    }

    /// Display help and exit.
    pub fn help(this: Program) noreturn {
        if (!@hasDecl(root, "help")) {
            @compileError("program does not define 'help' in root module");
        }

        this.tpl(root.help);
        std.process.exit(0);
    }

    /// Non-blocking, safe write to STDOUT
    pub fn out(this: Program, comptime format: []const u8, args: anytype) void {
        this.stderr.print(format, args) catch {};
    }

    /// Write template to STDOUT, program fields to '{field}' sequences.
    fn tpl(this: Program, comptime template: []const u8) void {
        var i: usize = 0;

        while (std.mem.indexOfScalarPos(u8, template, i, '{')) |start| {
            if (std.mem.indexOfScalarPos(u8, template, start, '}')) |end| {
                const name = template[start + 1 .. end];

                if (std.mem.eql(u8, "cmd", name)) {
                    this.out("{s}{s}", .{ template[i..start], this.cmd });
                }

                i = end + 1;
            }
        }

        this.out("{s}", .{template[i..]});
    }

    /// Display version and exit.
    pub fn version(this: Program) noreturn {
        if (!@hasDecl(root, "version")) {
            @compileError("program does not define 'version' in root module");
        }

        this.out(root.version, .{});
        std.process.exit(0);
    }
};
