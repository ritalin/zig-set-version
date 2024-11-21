//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.
const std = @import("std");

pub fn readCurrent(allocator: std.mem.Allocator, source: [:0]const u8) ![]const u8 {
    const range = try readVersionInternal(allocator, source);

    return allocator.dupe(u8, source[range.start..range.end]);
}

pub fn currentVersion(allocator: std.mem.Allocator) ![]const u8 {
    const path = try std.fs.cwd().realpathAlloc(allocator, "build.zig.zon");
    defer allocator.free(path);

    const source = try readBuildZon(allocator, path);
    defer allocator.free(source);

    return readCurrent(allocator, source);
}

test "show current version" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = "1.2.3";

    const version = try readCurrent(allocator, source);
    defer allocator.free(version);

    try std.testing.expectEqualStrings(expect, version);
}

pub fn renew(allocator: std.mem.Allocator, source: [:0]const u8, new_version: std.SemanticVersion) ![]const u8 {
    const range = try readVersionInternal(allocator, source);

    return replaceVersion(allocator, source, range, new_version);
}

fn replaceVersion(allocator: std.mem.Allocator, source: [:0]const u8, range: std.zig.Token.Loc, version: std.SemanticVersion) ![]const u8 {
    const ver_str = try std.fmt.allocPrint(allocator, "{}", .{version});
    defer allocator.free(ver_str);

    var buf = try std.ArrayList(u8).initCapacity(allocator, source.len - (range.end - range.start) + ver_str.len);
    defer buf.deinit();
    var writer = buf.writer();

    try writer.writeAll(source[0..range.start]);
    try writer.writeAll(ver_str);
    try writer.writeAll(source[range.end..]);

   return buf.toOwnedSlice();
}

test "version renewal" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "0.0.1",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3",
        \\  .dependencies = .{},
        \\}
    ;

    const version = std.SemanticVersion{.major = 1, .minor = 2, .patch = 3};
    const result = try renew(allocator, source, version);
    defer allocator.free(result);

    try std.testing.expectEqualStrings(expect, result);
}

pub const VersionPart = enum {major, minor, patch};
pub const IncOptions = std.enums.EnumFieldStruct(enum {pre, build}, bool, true);

pub fn resolveIncArgs(args: []const []const u8) !struct{part: VersionPart, options: IncOptions} {
    var part: VersionPart = undefined;
    var options: IncOptions = .{.pre = false, .build = false};

    const DoneSet = std.enums.EnumSet(CommandArgKind);
    const part_set = DoneSet.init(.{.major = true, .minor = true, .patch = true});
    var done = DoneSet.initEmpty();

    for (args) |arg| {
        if (! std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownArg;
        }

        if (CommandArgMap.get(arg[2..])) |kind| {
            switch (kind) {
                .major => {
                    if (done.contains(kind)) return error.VersionPartMultiple; 
                    part = .major;
                    done.setUnion(part_set);
                },
                .minor => {
                    if (done.contains(kind)) return error.VersionPartMultiple; 
                    part = .minor;
                    done.setUnion(part_set);
                },
                .patch => {
                    if (done.contains(kind)) return error.VersionPartMultiple; 
                    part = .patch;
                    done.setUnion(part_set);
                },
                .@"keep-pre" => {
                    if (done.contains(kind)) return error.VersionOptMultiple; 
                    options.pre = true;
                    done.insert(kind);
                },
                .@"keep-build" => {
                    if (done.contains(kind)) return error.VersionOptMultiple; 
                    options.build = true;
                    done.insert(kind);
                },
            }
        }
        else {
            return error.UnknownArg;
        }
    }

    if (done.intersectWith(part_set).count() == 0) return error.VersionPartNotFound;

    return .{
        .part = part,
        .options = options,
    };
}

const CommandArgKind = enum {
    major,
    minor,
    patch,
    @"keep-pre",
    @"keep-build",
};

const CommandArgMap = std.StaticStringMap(CommandArgKind).initComptime(.{
    .{@tagName(.major), .major},
    .{@tagName(.minor), .minor},
    .{@tagName(.patch), .patch},
    .{@tagName(.@"keep-pre"), .@"keep-pre"},
    .{@tagName(.@"keep-build"),. @"keep-build"},
});

pub fn increment(allocator: std.mem.Allocator, source: [:0]const u8, part: VersionPart, keep_options: IncOptions) !struct{std.SemanticVersion, []const u8} {
    const range = try readVersionInternal(allocator, source);
    var version = try std.SemanticVersion.parse(source[range.start..range.end]);

    switch (part) {
        .major => {
            version.major += 1;
            version.minor = 0;
            version.patch = 0;
        },
        .minor => {
            version.minor += 1;
            version.patch = 0;
        },
        .patch => {
            version.patch += 1;
        }
    }

    if (! keep_options.build) {
        version.build = null;
    }
    if (! keep_options.pre) {
        version.pre = null;
        version.build = null;
    }

    return .{
        version,
        try replaceVersion(allocator, source, range, version),
    };
}

test "increment patch version with keeping build" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.4-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 1, .minor = 2, .patch = 4, .pre = "alpha", .build = "9876"};

    const version, const result = try increment(allocator, source, .patch, .{});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment patch version with keeping pre only" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.4-alpha",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 1, .minor = 2, .patch = 4, .pre = "alpha"};

    const version, const result = try increment(allocator, source, .patch, .{.build = false});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment patch version without keeping options#1" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.4",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 1, .minor = 2, .patch = 4};

    const version, const result = try increment(allocator, source, .patch, .{.pre = false, .build = false});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment patch version without keeping options#2" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.4",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 1, .minor = 2, .patch = 4};

    const version, const result = try increment(allocator, source, .patch, .{.pre = false, .build = true});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment minor version with keeping all" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.3.0-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 1, .minor = 3, .patch = 0, .pre = "alpha", .build = "9876"};

    const version, const result = try increment(allocator, source, .minor, .{});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment minor version without keeping all" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.3.0",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 1, .minor = 3, .patch = 0};

    const version, const result = try increment(allocator, source, .minor, .{.pre = false, .build = false});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment major version with keeping all" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "2.0.0-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 2, .minor = 0, .patch = 0, .pre = "alpha", .build = "9876"};

    const version, const result = try increment(allocator, source, .major, .{});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

test "increment major version without keeping all" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "2.0.0",
        \\  .dependencies = .{},
        \\}
    ;
    const expect_version = std.SemanticVersion{.major = 2, .minor = 0, .patch = 0};

    const version, const result = try increment(allocator, source, .major, .{.pre = false, .build = false});
    defer allocator.free(result);

    try std.testing.expectEqualDeep(expect_version, version);
    try std.testing.expectEqualStrings(expect, result);
}

pub fn readBuildZon(allocator: std.mem.Allocator, full_path: []const u8) ![:0]const u8 {
    var file = try std.fs.openFileAbsolute(full_path, .{});
    defer file.close();

    const meta = try file.metadata();
    return try file.readToEndAllocOptions(allocator, meta.size(), meta.size(), @alignOf(u8), 0);
}

fn readVersionInternal(allocator: std.mem.Allocator, source: [:0]const u8) !std.zig.Token.Loc {
    var ast = try std.zig.Ast.parse(allocator, source, .zon);
    defer ast.deinit(allocator);

    const node_links = ast.nodes.items(.data);
    const token_tags = ast.tokens.items(.tag);

    var buf: [2]std.zig.Ast.Node.Index = undefined;

    if (ast.fullStructInit(&buf, node_links[0].lhs)) |node| {
        for (node.ast.fields) |field_index| {
            const token_index = ast.firstToken(field_index) - 2;
            if (token_tags[token_index] != .identifier) continue;

            const field_name = ast.tokenSlice(token_index);

            if (std.mem.eql(u8, field_name, "version")) {
                const span = ast.nodeToSpan(field_index);
                return .{
                    .start = span.start + 1,
                    .end = span.end - 1,
                };
            }
        }
    }

    return error.InvalidFileFormat;
}

test "invalid zon format" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .dependencies = .{},
        \\}
    ;

    const result = readVersionInternal(allocator, source);
    try std.testing.expectError(error.InvalidFileFormat, result);
}

test "read invalid version from zon" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1,2,3",
        \\  .dependencies = .{},
        \\}
    ;

    const range = try readVersionInternal(allocator, source);
    const result = std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectError(error.InvalidVersion, result);
}

test "read version from zon" {
    const allocator = std.testing.allocator;

    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = std.SemanticVersion{
        .major = 1, .minor = 2, .patch = 3, 
    };
    const range = try readVersionInternal(allocator, source);
    const version = try std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectEqualDeep(expect, version);
}

test "read version with pre-release from zon" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-beta",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = std.SemanticVersion{
        .major = 1, .minor = 2, .patch = 3, 
        .pre = "beta",
    };
    const range = try readVersionInternal(allocator, source);
    const version = try std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectEqualDeep(expect, version);
}

test "read version with build-meta from zon" {
    const allocator = std.testing.allocator;
    
    const source = 
        \\.{
        \\  .name = "SomeProject",
        \\  .version = "1.2.3-alpha+9876",
        \\  .dependencies = .{},
        \\}
    ;
    const expect = std.SemanticVersion{
        .major = 1, .minor = 2, .patch = 3, 
        .pre = "alpha", .build = "9876",
    };
    const range = try readVersionInternal(allocator, source);
    const version = try std.SemanticVersion.parse(source[range.start..range.end]);

    try std.testing.expectEqualDeep(expect, version);
}