const std = @import("std");
const op = @import("operator.zig");

pub fn addStep(build: *std.Build) void {
    const task = build.step("version", "Mnage project version");
    const step = CommandStep.init(build, task.name) catch @panic("OOM");

    task.dependOn(&step.step);
}

const CommandStep = struct {
    step: std.Build.Step,

    pub fn init(owner: *std.Build, name: []const u8) !*CommandStep {
        const self = try owner.allocator.create(CommandStep);
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = name,
                .owner = owner,
                .makeFn = make,
            }),
        };

        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        const self: *CommandStep = @fieldParentPtr("step", step);
        const builder = self.step.owner;
        _ = options;

        const path =
            std.Io.Dir.cwd().realPathFileAlloc(builder.graph.io, "build.zig.zon", builder.allocator)
            catch {
                return step.fail("`build.zig.zon` is not found", .{});
            };
        defer builder.allocator.free(path);

        const content = try op.readBuildZon(builder.graph.io, builder.allocator, path);
        defer builder.allocator.free(content);

        if (builder.args) |args| {
            const subcommand = std.meta.stringToEnum(Subcommand, args[0]);

            try processCommand(builder.graph.io, builder.allocator, step, subcommand orelse .show, args, content);
        }
        else {
            try processCommand(builder.graph.io, builder.allocator, step, .show, &.{}, content);
        }
    }
};

const Subcommand = enum {
    help,
    show,
    renew,
    inc,
};

fn processCommand(io: std.Io, allocator: std.mem.Allocator, step: *std.Build.Step, subcommand: Subcommand, args: []const []const u8, content: [:0]const u8) !void {
    const new_version, const new_content = result: {
        switch (subcommand) {
            .help => {
                step.result_stderr = try showUsage();
                return;
            },
            .show => {
                step.result_stderr = try op.readCurrent(allocator, content);
                return;
            },
            .renew => {
                if (args.len < 2) {
                    return step.fail("Need to specify version (Usage: `zig build version -- {s} \"1.2.3\"`)", .{@tagName(subcommand)});
                }

                const version: std.SemanticVersion =
                    std.SemanticVersion.parse(args[1])
                    catch {
                        return step.fail("Invalid version number", .{});
                    };

                break:result .{
                    version,
                    try op.renew(allocator, content, version),
                };
            },
            .inc => {
                if (args.len < 2) {
                    return step.fail("Need to specify version (Usage: `zig build version -- {s} --major`)", .{@tagName(subcommand)});
                }
                const inc_args = op.resolveIncArgs(args[1..])
                catch |err| {
                    return step.fail(
                        "{s}", .{
                            switch (err) {
                                error.VersionPartNotFound => "Need to specify exactly one version part",
                                error.VersionPartMultiple => "Need to specify one of `--major <VAL>`, `--minor <VAL>` and `--patch <VAL>`",
                                error.VersionOptMultiple => "`--keep-patch` and `--keep-build` is duplicated",
                                else => "Containing unknown arg",
                            }
                        }
                    );
                };

                const new_version, const new_content = try op.increment(allocator, content, inc_args.part, inc_args.options);

                break:result .{
                    new_version,
                    new_content,
                };
            },
        }
    };
    defer allocator.free(new_content);

    var buffer: [4096]u8 = undefined;
    var tmp_file = try std.Io.Dir.createFileAtomic(
        std.Io.Dir.cwd(),
        io,
        "build.zig.zon",
        .{},
    );
    defer tmp_file.deinit(io);

    var writer = tmp_file.file.writer(io,& buffer);
    try writer.interface.writeAll(new_content);
    try writer.flush();
    try tmp_file.replace(io);

    step.result_stderr = try std.fmt.allocPrint(allocator, "Updated to `{f}`", .{new_version});
}

fn showUsage() ![]const u8 {
    return
        \\Usage:
        \\zig build version -- <CMD> <ARG> ...
        \\The following is supported subcommands
        \\
        \\  help                    Show this messages
        \\  show                    Show the current version
        \\  renew <Sem-Ver>         Update specified the version
        \\  inc <Part> [<Option>]   Increment version part
        \\      <Part> is one of `--major`, `--minor` and `--patch`
        \\      <Option> are `--keep-pre` and/or `--keep-build`. Specify if want to keep pre and/or build part.
    ;
}
