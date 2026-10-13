const std = @import("std");
const op = @import("./operator.zig");
const step = @import("./step.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    
    var buffer: [4096]u8 = undefined;
    const t = std.debug.lockStderr(&buffer).terminal();
    defer std.debug.unlockStderr();

    const args = try init.minimal.args.toSlice(allocator);
    defer allocator.free(args);
    
    if (args.len < 2) {
        std.debug.print("Too few arguments", .{});
        std.debug.print("{s}\n", .{ try step.showUsage() });
        std.process.exit(1);
    }

    const manifest_path = args[1];
    const command_str, const rest_args = args: {
        if (args.len > 2) {
            break:args .{ args[2], args[3..] };
        }
        else {
            break:args .{ "show", &.{} };
        }
    };
    const command = std.meta.stringToEnum(step.Subcommand, command_str) orelse {
        std.debug.print("Unexpected subcommand/`{s}`\n", .{command_str});
        std.process.exit(1);
    };

    const path =
        std.Io.Dir.cwd().realPathFileAlloc(io, manifest_path, allocator)
        catch {
            std.debug.print("`build.zig.zon` is not found\n", .{});
            std.process.exit(1);
        }
    ;
    defer allocator.free(path);

    const content = try op.readBuildZon(io, allocator, path);
    defer allocator.free(content);

    try step.processCommand(io, allocator, t, command, rest_args, content);
}
