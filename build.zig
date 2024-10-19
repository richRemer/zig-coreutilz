const std = @import("std");
const Type = std.builtin.Type;

const build_spec = .{
    .src_path = "src",
    .deps = .{.iteropt},
    .exes = .{
        .false = .{},
        .seq = .{.iteropt},
        .true = .{},
        .uname = .{.iteropt},
    },
};

pub fn build(b: *std.Build) !void {
    try SpecBuild(build_spec).setup(b);
}

fn SpecBuild(comptime spec: anytype) type {
    return struct {
        pub fn setup(b: *std.Build) !void {
            var deps: Dependencies(spec) = .{};
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            const Spec = @TypeOf(spec);
            const allocator = arena.allocator();
            const target = b.standardTargetOptions(.{});
            const optimize = b.standardOptimizeOption(.{});

            inline for (@typeInfo(Dependencies(spec)).@"struct".fields) |f| {
                @field(deps, f.name) = b.dependency(f.name, .{
                    .target = target,
                    .optimize = optimize,
                });
            }

            if (@hasField(Spec, "exes")) {
                const exes_info = @typeInfo(@TypeOf(spec.exes));
                const src_fmt = "{s}/{s}.zig";

                inline for (exes_info.@"struct".fields) |f| {
                    const exe_spec = @field(spec.exes, f.name);
                    const exe_info = @typeInfo(f.type);
                    const exe = b.addExecutable(.{
                        .name = f.name,
                        .root_source_file = b.path(
                            try std.fmt.allocPrint(allocator, src_fmt, .{
                                spec.src_path,
                                f.name,
                            }),
                        ),
                        .target = target,
                        .optimize = optimize,
                    });

                    inline for (exe_info.@"struct".fields) |import| {
                        const dep_tag = @field(exe_spec, import.name);
                        const name = @tagName(dep_tag);
                        const dep = @field(deps, name).?;

                        exe.root_module.addImport(name, dep.module(name));
                    }

                    b.installArtifact(exe);
                }
            }
        }
    };
}

fn Dependencies(comptime spec: anytype) type {
    const Spec = @TypeOf(spec);
    const Deps = if (@hasField(Spec, "deps")) @TypeOf(spec.deps) else void;
    const deps_info = @typeInfo(Deps);
    const deps_len = if (Deps != void) deps_info.@"struct".fields.len else 0;

    comptime var fields: [deps_len]Type.StructField = undefined;

    if (deps_len > 0) {
        const nul = @typeInfo(Null(*std.Build.Dependency)).@"struct".fields[0].default_value;

        inline for (deps_info.@"struct".fields, 0..) |field, i| {
            const tag = @field(spec.deps, field.name);

            fields[i] = Type.StructField{
                .name = @tagName(tag),
                .type = ?*std.Build.Dependency,
                .alignment = @alignOf(?*std.Build.Dependency),
                .default_value = nul,
                .is_comptime = false,
            };
        }
    }

    return @Type(Type{
        .@"struct" = Type.Struct{
            .layout = .auto,
            .is_tuple = false,
            .fields = &fields,
            .decls = &[0]Type.Declaration{},
        },
    });
}

/// This piece of hackery is used to lookup a comptime *const anyopaque that
/// can be used to define StructField with a null default_value.
///
/// In order to obtain the value:
/// @typeInfo(Null(T)).@"struct".fields[0].default_value
fn Null(comptime T: type) type {
    return struct { value: ?T = null };
}
