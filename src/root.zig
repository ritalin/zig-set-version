const std = @import("std");
const op = @import("./operator.zig");

pub const VersionSetterStep = @import("./step.zig");

pub fn currentVersion(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    return op.currentVersion(io, allocator);
}

test "test entry" {
    std.testing.refAllDecls(op);
}

test "currentVersion public API" {
    const version = try currentVersion(std.testing.io, std.testing.allocator);
    defer std.testing.allocator.free(version);
    try std.testing.expect(version.len > 0);
}
