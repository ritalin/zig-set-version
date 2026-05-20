const std = @import("std");
const op = @import("./operator.zig");

pub const VersionSetterStep = @import("./step.zig");

pub fn currentVersion(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    return op.currentVersion(io, allocator);
}

test "test entry" {
    std.testing.refAllDecls(op);
}
