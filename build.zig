const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_unit_tests = b.addTest(.{
        .root_module = b.addModule("set-version", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = true,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&b.addInstallArtifact(exe_unit_tests, .{.dest_sub_path = "../test/test-set-version"}).step);
}

pub const VersionSetterStep = @import("./src/root.zig").VersionSetterStep;
pub const currentVersion = @import("./src/root.zig").currentVersion;
