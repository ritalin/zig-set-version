const std = @import("std");

pub const VersionSetterStep = @import("./step.zig");

test "test entry" {
    std.testing.refAllDecls(@import("./operator.zig"));
}