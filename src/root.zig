const std = @import("std");
const op = @import("./operator.zig");

pub const VersionSetterStep = @import("./step.zig");

pub fn currentVersion(allocator: std.mem.Allocator) ![]const u8 {
    return op.currentVersion(allocator);
}

test "test entry" {
    std.testing.refAllDecls(op);
}