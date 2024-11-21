const std = @import("std");

pub const VersionSetterStep = @import("./version.zig");

test "test entry" {
    std.testing.refAllDecls(@This());
}